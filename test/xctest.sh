#! /bin/sh
##
## xctest.sh --
##
##   Test script for Xcluster.
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

##   k8s_wait [--no-coredns]
##     Wait for Kubernetes. When CoreDNS is Running k8s is assumed to be ready.
##
cmd_k8s_wait() {
	tcase "Kubernetes check"

	# Check connectivity
	test -n "$__nvm" || __nvm=4
	test -n "$__nrouters" || __nrouters=2
	test -n "$__ntesters" || __ntesters=0

	tex check_vm $(seq 1 $__nvm) $(seq 201 $((200+__nrouters))) \
		$(seq 221 $((220+__ntesters))) || tdie
	tlog "VMs OK"

	tex "rsh 1 kubectl get nodes 2>&1 | ogrep -qE 'Ready'"
	tlog "Nodes Ready"

	test "$__no_coredns" = "yes" && return 0
	pushv 30 15 2
	tex "rsh 1 kubectl get pods 2>&1 | ogrep -qE '^coredns.*Running'"
	popv
	tlog "CoreDNS Running"

	return 0
}


##   test --list
##   test [--xterm] [test...] > logfile
##     Test xcluster
##
cmd_test() {
	if test "$__list" = "yes"; then
		grep '^test_' $me | cut -d'(' -f1 | sed -e 's,test_,,'
		return 0
	fi

	test -n "$XCLUSTER" || die 'Not set [$XCLUSTER]'
	test -x "$XCLUSTER" || die "Not executable [$XCLUSTER]"
	eval $($XCLUSTER env)

	start=starts
	test "$__xterm" = "yes" && start=start

	# Remove overlays
	rm -f $XCLUSTER_TMP/cdrom.iso
	
	# Go!
	begin=$(date +%s)
	tlog "Xcluster test started $(date +%F)"
	__timeout=10

	if test -n "$1"; then
		for t in $@; do
			test_$t
		done
	else
		for t in basic k8s k8s_ipv6 k8s_kube_router k8s_metallb; do
			test_$t
		done
	fi	

	now=$(date +%s)
	tlog "Xcluster test ended. Total time $((now-begin)) sec"
}

test_basic() {
	tcase "Start xcluster"

	# Use the standard image (not k8s)
	export __image=$XCLUSTER_HOME/hd.img

	$XCLUSTER $start
	sleep 2

	tcase "VM connectivity"
	tex check_vm || tdie

	tcase "Scale out to 8 vms"
	$XCLUSTER scaleout 5 6 7 8
	sleep 2
	tex check_vm 1 2 3 4 5 6 7 8 201 202 || tdie

	tcase "Scale in some vms"
	$XCLUSTER scalein 2 4 6 8 202
	sleep 0.5
	tex check_vm 1 3 5 7 201 || tdie
	check_novm 2 4 6 8 202

	tcase "Stop xcluster"
	$XCLUSTER stop
}
test_k8s() {
	# Kubernetes tests;
	tcase "Start xcluster"
	$XCLUSTER mkcdrom externalip test $__xovl
	$XCLUSTER $start
	sleep 2

	tcase "VM connectivity"
	tex check_vm || tdie

	tcase "Perform on-cluster tests"
	rsh 4 xctest k8s || tdie	
	rsh 201 xctest router_k8s || tdie

	test "$__no_stop" = "yes" && return 0
	tcase "Stop xcluster"
	$XCLUSTER stop
}
test_k8s_ipv6() {
	# Kubernetes tests with ipv6-only;
	tcase "Start xcluster with k8s ipv6-only"
	# Make sure "k8s-config" is last
	SETUP=ipv6 $XCLUSTER mkcdrom etcd externalip test $__xovl k8s-config
	$XCLUSTER $start
	sleep 2

	tcase "VM connectivity"
	tex check_vm || tdie

	tcase "Perform on-cluster tests"
	rsh 4 xctest k8s --ipv6 || tdie
	rsh 201 xctest router_k8s --ipv6 || tdie

	test "$__no_stop" = "yes" && return 0
	tcase "Stop xcluster"
	$XCLUSTER stop
}
test_k8s_kube_router() {
	# Kubernetes tests with kube-router;
	tcase "Start xcluster with kube-router"
	$XCLUSTER mkcdrom gobgp kube-router test $__xovl
	$XCLUSTER $start
	sleep 2

	tcase "VM connectivity"
	tex check_vm || tdie

	tcase "Perform on-cluster tests"
	rsh 4 xctest k8s_kube_router || tdie	
	rsh 201 xctest router_kube_router || tdie

	test "$__no_stop" = "yes" && return 0
	tcase "Stop xcluster"
	$XCLUSTER stop
}

test_k8s_metallb() {
	# Kubernetes tests with kube-router;
	tcase "Start xcluster for test with metallb"
	$XCLUSTER mkcdrom gobgp metallb test $__xovl
	$XCLUSTER $start
	sleep 2

	tcase "VM connectivity"
	tex check_vm || tdie

	tcase "Wait for Kubernetes"
	rsh 4 xctest wait_for_k8s --no-coredns || tdie

	tcase_tiller
	tcase_helm_install_metallb
	rsh 4 xctest tcase_check_metallb || tdie
	rsh 4 xctest tcase_start_mconnect || tdie
	rsh 4 xctest tcase_check_loadbalancererip --timeout=90 || tdie
	rsh 201 xctest router_k8s || tdie

	test "$__no_stop" = "yes" && return 0
	tcase "Stop xcluster"
	$XCLUSTER stop
}

check_novm() {
	local vms='1 2 3 4 201 202'
	test -n "$1" && vms=$@
	for vm in $vms; do
		if ip link show xcbr1 > /dev/null 2>&1; then
			# In a netns we have "real" ip targets which means that a
			# connect may block for a long time. So use "nc" with a
			# timeout instead of ssh.
			echo hostname | nc -N -w 1 192.168.0.$vm 23 /dev/null && return 1
		else
			rsh $vm hostname && return 1
		fi
	done
	return 0
}
cmd_rsh() {
	test -n "$2" || die "Syntax err"
	rsh $@
}

tcase_tiller() {
	tcase "Start tiller"
	netstat -putan | grep ':44134 ' && return 0
	which tiller > /dev/null || tdie "Tiller not found"
	tiller > /tmp/$USER/tiller.log 2>&1 &
	sleep 0.5
}
tcase_helm_install_metallb() {
	tcase "Install metallb with helm"
	which helm > /dev/null || tdie "Helm not found"
	test -n "$HELM_HOST" || export HELM_HOST=localhost:44134
	helm install --name metallb stable/metallb 2>&1 || tdie Helm
	sleep 2
	pushv 30 15 2
	tex "kubectl get pods | ogrep -qE '^metallb-controller.*Running'"
	popv
	kubectl apply -f \
		$($XCLUSTER ovld metallb)/default/etc/kubernetes/metallb-config-helm.yaml
}


. $($XCLUSTER ovld test)/default/usr/lib/xctest
indent=''


# Get the command
cmd=$1
shift
grep -q "^cmd_$cmd()" $0 || die "Invalid command [$cmd]"

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
