#! /bin/sh
##
## test-template.sh --
##
##   Help script for the xcluster ovl/test-template.
##
## Commands;
##

prg=$(basename $0)
dir=$(dirname $0); dir=$(readlink -f $dir)
me=$dir/$prg
tmp=/tmp/${prg}_$$

die() {
    echo "ERROR: $*" >&2
    rm -rf $tmp
    exit 1
}
help() {
    grep '^##' $0 | cut -c3-
    rm -rf $tmp
    exit 0
}
test -n "$1" || help
echo "$1" | grep -qi "^help\|-h" && help

log() {
	echo "$prg: $*" >&2
}
dbg() {
	test -n "$__verbose" && echo "$prg: $*" >&2
}

##  env
##    Print environment.
##
cmd_env() {

	if test "$cmd" = "env"; then
		set | grep -E '^(__.*)='
		retrun 0
	fi

	test -n "$XCLUSTER" || die 'Not set [$XCLUSTER]'
	test -x "$XCLUSTER" || die "Not executable [$XCLUSTER]"
	eval $($XCLUSTER env)
}

##   test --list
##   test [--xterm] [test...] > logfile
##     Exec tests
##
cmd_test() {
	if test "$__list" = "yes"; then
        grep '^test_' $me | cut -d'(' -f1 | sed -e 's,test_,,'
        return 0
    fi

	cmd_env
    start=starts
    test "$__xterm" = "yes" && start=start
    rm -f $XCLUSTER_TMP/cdrom.iso

    if test -n "$1"; then
        for t in $@; do
            test_$t
        done
    else
        for t in basic4 basic6 basic_dual; do
            test_$t
        done
    fi      

    now=$(date +%s)
    tlog "Xcluster test ended. Total time $((now-begin)) sec"

}

test_start() {
	test -n "$__mode" || __mode=dual-stack
	xcluster_prep $__mode
	xcluster_start test-template

	otc 1 check_namespaces
	otc 1 check_nodes
	otc 2 check_coredns
}

test_basic4() {
	basic ipv4
}

test_basic6() {
	basic ipv6
}

test_basic_dual() {
	basic dual-stack
}

basic() {
	tlog "=== test-template: Basic test on $1"

	__mode=$1
	test_start

	otc 2 start_alpine
	otc 3 "start_mconnect $1"
	otc 2 check_alpine
	otc 2 "check_pod_addresses $1"
	otc 2 "nslookup mconnect.default.svc.xcluster"
	otc 3 "internal_mconnect $1"
	otc 3 "nslookup www.google.se"
	otc 3 pod_nslookup
	otc 201 set_vip_routes
	if test "$1" = "ipv4" -o "$1" = "ipv6"; then
		otc 201 "external_mconnect $1"
	else
		otc 201 "external_mconnect ipv4"
		otc 201 "external_mconnect ipv6"
	fi

	xcluster_stop
}


cmd_otc() {
	test -n "$__vm" || __vm=2
	otc $__vm $@
}

. $($XCLUSTER ovld test)/default/usr/lib/xctest
indent=''

# Get the command
cmd=$1
shift
grep -q "^cmd_$cmd()" $0 $hook || die "Invalid command [$cmd]"

while echo "$1" | grep -q '^--'; do
    if echo $1 | grep -q =; then
	o=$(echo "$1" | cut -d= -f1 | sed -e 's,-,_,g')
	v=$(echo "$1" | cut -d= -f2-)
	eval "$o=\"$v\""
    else
	o=$(echo "$1" | sed -e 's,-,_,g')
	eval "$o=yes"
    fi
    shift
done
unset o v
long_opts=`set | grep '^__' | cut -d= -f1`

# Execute command
trap "die Interrupted" INT TERM
cmd_$cmd "$@"
status=$?
rm -rf $tmp
exit $status
