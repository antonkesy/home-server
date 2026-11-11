# One JSON snapshot of lab for the start page (modules/overview.nix): the
# machine's cpu, memory, disks and network, and what each service takes of
# them. CPU and network are rates, so both are measured over one second.
# Reads /proc, sysfs and the cgroup tree only; df is a statfs, so the array's
# disks stay asleep.
shopt -s nullglob
cg=/sys/fs/cgroup

# a container runs in a scope of its own; the id oci-containers writes next to
# it says whose
declare -A owner=()
for f in /run/*/ctr-id; do
  name=${f#/run/}
  owner["$(<"$f")"]=podman-${name%/ctr-id}
done

# a row per service, per template (its instances share a slice), per
# container, and one for the login sessions
declare -A unit=()
for d in "$cg"/system.slice/*.service; do
  n=${d##*/}
  unit["$d"]=${n%.service}
done
for d in "$cg"/system.slice/system-*.slice; do
  n=${d##*/system-}
  n=${n%.slice}
  unit["$d"]=${n//\\x2d/-}
done
for d in "$cg"/machine.slice/libpod-*.scope; do
  id=${d##*/libpod-}
  id=${id%.scope}
  unit["$d"]=${owner["$id"]:-podman}
done
if [ -d "$cg/user.slice" ]; then
  unit["$cg/user.slice"]=logins
fi

# the interface the default route leaves by
iface=""
while read -r ifc dest _; do
  if [ "$dest" = 00000000 ]; then
    iface=$ifc
    break
  fi
done </proc/net/route

# cpu time per cgroup into `usage`, the machine's busy and total jiffies,
# bytes moved
declare -A usage=()
sample() {
  local d k v
  for d in "${!unit[@]}"; do
    usage["$d"]=0
    [ -r "$d/cpu.stat" ] || continue
    while read -r k v; do
      if [ "$k" = usage_usec ]; then
        usage["$d"]=$v
        break
      fi
    done <"$d/cpu.stat" || true
  done
  local u n s i w q sq st
  read -r _ u n s i w q sq st _ </proc/stat
  all=$((u + n + s + i + w + q + sq + st))
  busy=$((all - i - w))
  rx=0 tx=0
  if [ -n "$iface" ]; then
    rx=$(<"/sys/class/net/$iface/statistics/rx_bytes")
    tx=$(<"/sys/class/net/$iface/statistics/tx_bytes")
  fi
  now=${EPOCHREALTIME//[!0-9]/}
}

declare -A cpu0=()
sample
for d in "${!usage[@]}"; do
  cpu0["$d"]=${usage["$d"]}
done
all0=$all busy0=$busy rx0=$rx tx0=$tx t0=$now
sleep 1
sample
elapsed=$((now - t0))

# without the page cache: jellyfin reading a film is not jellyfin's memory
rows() {
  local d k v cur file
  for d in "${!unit[@]}"; do
    # a unit that stopped since the listing is skipped
    cur=$(cat "$d/memory.current" 2>/dev/null) || continue
    file=0
    while read -r k v; do
      case $k in
        active_file | inactive_file) file=$((file + v)) ;;
      esac
    done <"$d/memory.stat" || continue
    printf '%s\t%s\t%s\n' "${unit["$d"]}" "$((usage["$d"] - cpu0["$d"]))" "$((cur - file))"
  done
}

memtotal=0 memavail=0 swaptotal=0 swapfree=0
while read -r k v _; do
  case $k in
    MemTotal:) memtotal=$v ;;
    MemAvailable:) memavail=$v ;;
    SwapTotal:) swaptotal=$v ;;
    SwapFree:) swapfree=$v ;;
  esac
done </proc/meminfo
read -r l1 l5 l15 _ </proc/loadavg
read -r up _ </proc/uptime

# the package sensor, else the first one that reads; a sensor can refuse
temp=null
for z in /sys/class/thermal/thermal_zone*; do
  if [ "$(cat "$z/type" 2>/dev/null)" = x86_pkg_temp ] && t=$(cat "$z/temp" 2>/dev/null); then
    temp=$((t / 1000))
    break
  fi
done
if [ "$temp" = null ]; then
  for z in /sys/class/thermal/thermal_zone*; do
    if t=$(cat "$z/temp" 2>/dev/null); then
      temp=$((t / 1000))
      break
    fi
  done
fi

# an unmounted mountpoint would report / again
mounts=(/)
if findmnt -n --mountpoint "$LAB_STORAGE" >/dev/null; then
  mounts+=("$LAB_STORAGE")
fi

jq -n \
  --argjson elapsed "$elapsed" \
  --argjson cores "$(nproc)" \
  --argjson busy "$((busy - busy0))" \
  --argjson all "$((all - all0))" \
  --argjson l1 "$l1" --argjson l5 "$l5" --argjson l15 "$l15" \
  --argjson temp "$temp" \
  --argjson memtotal "$memtotal" --argjson memavail "$memavail" \
  --argjson swaptotal "$swaptotal" --argjson swapfree "$swapfree" \
  --arg iface "$iface" \
  --argjson rx "$((rx - rx0))" --argjson tx "$((tx - tx0))" \
  --argjson uptime "${up%.*}" \
  --rawfile disks <(df -B1 --output=target,size,used "${mounts[@]}" | tail -n +2) \
  --rawfile units <(rows) \
  '{
    cpu: {
      pct: (if $all > 0 then 100 * $busy / $all else 0 end),
      cores: $cores, load: [$l1, $l5, $l15], temp: $temp
    },
    mem: {total: ($memtotal * 1024), used: (($memtotal - $memavail) * 1024)},
    swap: {total: ($swaptotal * 1024), used: (($swaptotal - $swapfree) * 1024)},
    disks: [$disks | split("\n")[] | select(length > 0)
      | [splits(" +")] | map(select(length > 0))
      | {mount: .[0], size: (.[1] | tonumber), used: (.[2] | tonumber)}],
    net: {iface: $iface, rx: ($rx * 1e6 / $elapsed), tx: ($tx * 1e6 / $elapsed)},
    uptime: $uptime,
    # cpu as a share of the whole machine, so the rows add up to the total
    units: ([$units | split("\n")[] | select(length > 0) | split("\t")
        | {name: .[0], cpu: (.[1] | tonumber), mem: (.[2] | tonumber)}]
      | group_by(.name)
      | map({
          name: .[0].name,
          cpu: ([0, 100 * (map(.cpu) | add) / $elapsed / $cores] | max),
          mem: ([0, (map(.mem) | add)] | max)
        })
      | map(select(.mem > 0 or .cpu > 0)))
  }'
