#! /bin/sh
##
## kubeadm.sh --
##
##   Help script for the xcluster ovl/kubeadm.
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
	echo "$*" >&2
}
eset() {
	local e k
	for e in $@; do
		k=$(echo $e | cut -d= -f1)
		opts="$opts|$k"
		test -n "$(eval echo \$$k)" || eval $e
		test "$(eval echo \$$k)" = "?" && eval $e
	done
}

##  env
##    Print environment.
##
cmd_env() {
	test "$envset" = "yes" && return 0
	envset=yes
	eset \
		__nvm=4 \
		__nrouters=1 \
		__k8sver=v1.30.0 \
		__cni=bridge \
		__mem1=2048 \
		__mem=1536 \
		__cni=bridge \
		xcluster_DOMAIN=cluster.local \
		PREFIX=fd00:
	export __mem1 __mem xcluster_DOMAIN __k8sver
	export xcluster_PREFIX=$PREFIX
	if test "$cmd" = "env"; then
		set | grep -E "^($opts)="
		exit 0
	fi

	test -n "$XCLUSTER" || die 'Not set [$XCLUSTER]'
	test -x "$XCLUSTER" || die "Not executable [$XCLUSTER]"
	eval $($XCLUSTER env)
	test -n "$KUBERNETESD" || \
		export KUBERNETESD=$HOME/tmp/kubernetes/kubernetes-$__k8sver/server/bin	
	kubeadm=$KUBERNETESD/kubeadm
	test -n "$long_opts" && export $long_opts
}
##   cache_images
##     Download the K8s release images to the local private registry.
cmd_cache_images() {
	local i images
	images=$($XCLUSTER ovld images)/images.sh
	for i in $($kubeadm config images list --kubernetes-version $__k8sver); do
		if $images lreg_isloaded $i; then
			log "Already cached [$i]"
		else
			$images lreg_cache $i || die
			log "Cached [$i]"
		fi
	done
}

##
##   test [--xterm] [test...] > logfile
##     Exec tests
cmd_test() {
	test "$__k8sver" = "master" && die "Can't install [master]"
	test -x $kubeadm || die "Not executable [$kubeadm]"
	test -n "$long_opts" && export $long_opts
	start=starts
	test "$__xterm" = "yes" && start=start
	rm -f $XCLUSTER_TMP/cdrom.iso

	local t=default
	if test -n "$1"; then
		local t=$1
		shift
	fi		

	if test -n "$__log"; then
		mkdir -p $(dirname "$__log")
		date > $__log || die "Can't write to log [$__log]"
		test_$t $@ >> $__log
	else
		test_$t $@
	fi

	now=$(date +%s)
	log "Xcluster test ended. Total time $((now-begin)) sec"
}
##   test default
##     Install, start a deployment, and stop
test_default() {
	test_start $@
	otc 1 "deployment alpine"
	xcluster_stop
}

##   test start_empty
##     Start an empty cluster, but with crio and kubeadm
test_start_empty() {
	cmd_cache_images 2>&1
	export __image=$XCLUSTER_WORKSPACE/xcluster/hd.img
	unset BASEOVLS
	unset XOVLS
	if test "$__hugep" = "yes"; then
		local n
		for n in $(seq $FIRST_WORKER $__nvm); do
			eval export __append$n="hugepages=128"
		done
	fi
	xcluster_start network-topology test crio iptools private-reg k8s-cni-$__cni . $@
	test "$__hugep" = "yes" && otcwp mount_hugep
}
##   test [--k8sver=] start 
##     Start a cluster and install K8s using kubeadm
test_start() {
	test_start_empty $@
	#otcwp bogus_default_route
	otc 1 "pull_images $__k8sver"
	otc 1 "init_dual_stack $__k8sver"
	otc 1 check_namespaces
	otc 1 rm_coredns_deployment
	otc 1 install_cni

	for i in $(seq 2 $__nvm); do
		otc $i join
		otc $i coredns_k8s
		otc $i get_kubeconfig
	done

	otc 1 "check_nodes $__nvm"
	otc 1 check_nodes_ready
}
##   test [--wait] start_app
##     Start with a tserver app. This requires ovl/k8s-test
test_start_app() {
	$XCLUSTER ovld k8s-test > /dev/null 2>&1 || tdie "No ovl/k8s-test"
	__hugep=yes
	export KUBEADM_TEST=yes
	test_start k8s-test mconnect $@

	otcprog=k8s-test_test
	test "$__wait" = "yes" && otc 1 wait
	otc 1 "svc tserver 10.0.0.0"
	otc 1 "deployment --replicas=$__replicas tserver"
}

##
__mem=?; __mem1=?; __nvm=?  # set these in cmd_env
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
	long_opts="$long_opts $o"
	shift
done
unset o v

# Execute command
trap "die Interrupted" INT TERM
cmd_env
cmd_$cmd "$@"
status=$?
rm -rf $tmp
exit $status
