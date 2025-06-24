podman logs -f polaris | awk '
/ - [A-Z][a-z]+ \[/ {

    split($0, tmp, " - ");         # tmp[2] contains  "Alice [26/May/…"
    split(tmp[2], who, " ");       # who[1] → Alice
    principal = who[1];

    match($0, /"([A-Z]+) ([^ ]+) HTTP\/[0-9.]+"/, m);
    verb = m[1];   url = m[2];

    match($0, /" [0-9]{3} /);                  # RSTART points at space-code-space
    code = substr($0, RSTART+2, 3);

    green="\033[1;32m"; red="\033[1;31m"; reset="\033[0m";
    colour = (code ~ /^2/) ? green : (code ~ /^4/) ? red : reset;

    printf "%-8s %-4s %-55s %s%s%s\n",
           principal, verb, url, colour, code, reset;
}
'
