#! /bin/sh
##
## usrsctp.sh --
##
##   Help script for the xcluster ovl/usrsctp.
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

	test -n "$__tag" || __tag="registry.nordix.org/cloud-native/usrsctp-test:latest"

	if test "$cmd" = "env"; then
		set | grep -E '^(__.*)='
		return 0
	fi

	test -n "$xcluster_DOMAIN" || xcluster_DOMAIN=xcluster
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
	rm -f $($XCLUSTER ovld usrsctp)/captures/*.pcap
	export xcluster_PROXY_MODE=iptables

    if test -n "$1"; then
        for t in $@; do
            test_$t
        done
    else
		test_k8s_server
    fi      

    now=$(date +%s)
    tlog "Xcluster test ended. Total time $((now-begin)) sec"
}

test_client() {
	. ./network-topology/Envsettings

	export __image=$XCLUSTER_HOME/hd.img
	test -r $__image || die "Not readable [$__image]"

	xcluster_start iptools network-topology usrsctp

	otc 201 "check_discard_init"
	otc 221 "start_server_router 192.168.3.221 7003"
	otc 222 "start_server_router 192.168.3.222 7003"

	otc 201 vip_ecmp_route
	otc 202 "vip_ecmp_route 2"

	otc 1 "start_tcpdump eth1"
	otc 2 "start_tcpdump eth1"
	otc 221 "start_tcpdump eth1"
	otc 222 "start_tcpdump eth1"

	otc 1 "start_client_vm 192.168.3.221 7003 192.168.1.1 7003"
	otc 2 "start_client_vm 192.168.3.222 7003 192.168.1.2 7003"

	otc 201 "test_conntrack 2"
	otc 201 "test_conntrack 0"

	otc 1 stop_all_tcpdump
	otc 2 stop_all_tcpdump
	otc 221 stop_all_tcpdump
	otc 222 stop_all_tcpdump

	sleep 5

	rcp 1 /var/log/*.pcap captures/
	rcp 2 /var/log/*.pcap captures/
	rcp 221 /var/log/*.pcap captures/
	rcp 222 /var/log/*.pcap captures/
}

test_client_mh() {
	. ./network-topology/Envsettings

	export __image=$XCLUSTER_HOME/hd.img
	test -r $__image || die "Not readable [$__image]"

	xcluster_start iptools network-topology usrsctp

	otc 201 "check_discard_init"
	otc 202 "check_discard_init"
	otc 221 "start_server_router 192.168.3.221,192.168.4.221 7003"
	otc 222 "start_server_router 192.168.3.222,192.168.4.222 7003"

	otc 201 vip_ecmp_route
	otc 202 "vip_ecmp_route 2"

	otc 2 "start_tcpdump eth1"
	otc 2 "start_tcpdump eth2"
	otc 221 "start_tcpdump eth1"
	otc 221 "start_tcpdump eth2"

	otc 1 "start_client_vm 192.168.3.221,192.168.4.221 7003 192.168.1.1 7003"
	otc 2 "start_client_vm 192.168.3.222,192.168.4.222 7003 192.168.1.2 7003"

	otc 201 "test_conntrack 2"
	otc 202 "test_conntrack 2"
	otc 201 "test_conntrack 0"
	otc 202 "test_conntrack 0"

	otc 2 stop_all_tcpdump
	otc 221 stop_all_tcpdump

	sleep 5

	rcp 2 /var/log/*.pcap captures/
	rcp 221 /var/log/*.pcap captures/
}

test_server() {
	. ./network-topology/Envsettings

	export __image=$XCLUSTER_HOME/hd.img
	test -r $__image || die "Not readable [$__image]"

	xcluster_start iptools network-topology usrsctp

	otc 201 "check_discard_init"
	otc 202 "check_discard_init"
	otc 1 "start_server_vm 192.168.1.1 7003"
	otc 2 "start_server_vm 192.168.1.2 7003"

	otc 201 vip_ecmp_route
	otc 202 "vip_ecmp_route 2"

	otc 1 "start_tcpdump eth1"
	otc 2 "start_tcpdump eth1"
	otc 221 "start_tcpdump eth1"
	otc 222 "start_tcpdump eth1"

	otc 221 "start_client_router 192.168.3.201 7003 192.168.3.221 6001"
	otc 222 "start_client_router 192.168.3.201 7003 192.168.3.222 6002"

	otc 201 "test_conntrack 2"
	otc 201 "test_conntrack 0"

	otc 1 stop_all_tcpdump
	otc 2 stop_all_tcpdump
	otc 221 stop_all_tcpdump
	otc 222 stop_all_tcpdump

	sleep 5

	rcp 1 /var/log/*.pcap captures/
	rcp 2 /var/log/*.pcap captures/
	rcp 221 /var/log/*.pcap captures/
	rcp 222 /var/log/*.pcap captures/
}

test_k8s_client() {
	. ./network-topology/Envsettings.k8s

	__image=$XCLUSTER_HOME/hd-k8s-$__k8sver.img
	test -r $__image || __image=$XCLUSTER_HOME/hd-k8s.img
	export __image
	test -r $__image || die "Not readable [$__image]"

	xcluster_start iptools network-topology usrsctp

	otc 1 check_namespaces
	otc 1 check_nodes
	otc 221 start_server_router
	otc 2 "check_discard_init"

	otc 201 vip_ecmp_route
	otc 202 "vip_ecmp_route 2"

	otc 2 "start_tcpdump eth1"
	otc 2 "start_tcpdump eth2"
	otc 221 "start_tcpdump eth1"
	otc 221 "start_tcpdump eth2"

	otc 2 deploy_client_pods
	otc 2 "start_tcpdump_proc_ns usrsctpt"

	otc 2 "test_conntrack 2"
	otc 2 "test_conntrack 0"

	otc 2 stop_all_tcpdump
	otc 221 stop_all_tcpdump

	sleep 5

	rcp 2 /var/log/*.pcap captures/
	rcp 221 /var/log/*.pcap captures/
}

test_k8s_client_calico() {
	. ./network-topology/Envsettings.k8s

	# Test with k8s-xcluster;
	__image=$XCLUSTER_HOME/hd-k8s-xcluster-$__k8sver.img
	test -r $__image || __image=$XCLUSTER_HOME/hd-k8s-xcluster.img
	export __image
	test -r $__image || die "Not readable [$__image]"
	export XCTEST_HOOK=$($XCLUSTER ovld k8s-xcluster)/xctest-hook
	export xcluster_FIRST_WORKER=2

	$($XCLUSTER ovld images)/images.sh lreg_preload k8s-cni-calico
	xcluster_start k8s-cni-calico iptools network-topology usrsctp

	otc 1 check_namespaces
	otc 1 check_nodes
	otc 221 start_server_router
	otc 2 "check_discard_init"

	otc 201 vip_ecmp_route
	otc 202 "vip_ecmp_route 2"

	otc 221 "start_tcpdump eth1"
	otc 221 "start_tcpdump eth2"

	otc 2 deploy_client_pods
	otc 2 "start_tcpdump_proc_ns usrsctpt"

	otc 2 "test_conntrack 2"
	otc 2 "test_conntrack 0"

	otc 2 stop_all_tcpdump
	otc 221 stop_all_tcpdump

	sleep 5

	rcp 2 /var/log/*.pcap captures/
	rcp 221 /var/log/*.pcap captures/
}

test_k8s_server() {
	. ./network-topology/Envsettings.k8s

	__image=$XCLUSTER_HOME/hd-k8s-$__k8sver.img
	test -r $__image || __image=$XCLUSTER_HOME/hd-k8s.img
	export __image
	test -r $__image || die "Not readable [$__image]"

	xcluster_start iptools network-topology usrsctp

	otc 1 check_namespaces
	otc 1 check_nodes
	# otc 1 deploy_kpng_pods
	otc 1 deploy_server_pods
	otc 2 "check_discard_init"

	otc 201 vip_ecmp_route
	otc 202 "vip_ecmp_route 2"

	otc 2 "start_tcpdump_proc_ns usrsctpt"
	otc 1 "start_tcpdump eth1"
	otc 2 "start_tcpdump eth1"

	otc 221 "start_client_router 10.0.0.72 7002 192.168.3.221 6001"
	otc 222 "start_client_router 10.0.0.72 7002 192.168.3.222 6002"

	otc 2 "test_conntrack 2"
	otc 2 "test_conntrack 0"

	otc 2 stop_all_tcpdump
	otc 1 stop_all_tcpdump

	sleep 5

	rcp 2 /var/log/*.pcap captures/
	rcp 1 /var/log/*.pcap captures/

}

test_k8s_server_calico() {
	. ./network-topology/Envsettings.k8s

	# Test with k8s-xcluster;
	__image=$XCLUSTER_HOME/hd-k8s-xcluster-$__k8sver.img
	test -r $__image || __image=$XCLUSTER_HOME/hd-k8s-xcluster.img
	export __image
	test -r $__image || die "Not readable [$__image]"
	export XCTEST_HOOK=$($XCLUSTER ovld k8s-xcluster)/xctest-hook
	export xcluster_FIRST_WORKER=2

	$($XCLUSTER ovld images)/images.sh lreg_preload k8s-cni-calico
	xcluster_start k8s-cni-calico iptools network-topology usrsctp

	otc 1 check_namespaces
	otc 1 check_nodes
	# otc 1 deploy_kpng_pods
	otc 1 deploy_server_pods
	otc 2 "check_discard_init"

	otc 201 vip_ecmp_route
	otc 202 "vip_ecmp_route 2"

	otc 2 "start_tcpdump_proc_ns usrsctpt"

	otc 221 "start_client_router 10.0.0.72 7002 192.168.3.221 6001"
	otc 222 "start_client_router 10.0.0.72 7002 192.168.3.222 6002"

	otc 2 "test_conntrack 2"
	otc 2 "test_conntrack 0"

	otc 2 stop_all_tcpdump

	sleep 5

	rcp 2 /var/log/*.pcap captures/
}

##   nfqlb_download
##     Download a nfqlb release to $ARCHIVE
cmd_nfqlb_download() {
	NFQLB_VER="1.0.0"
	local ar=nfqlb-$NFQLB_VER.tar.xz
	local f=$ARCHIVE/$ar
	if test -r $f; then
		log "Already downloaded [$f]"
	else
		local url=https://github.com/Nordix/nfqueue-loadbalancer
		curl -L $url/releases/download/$NFQLB_VER/$ar > $f
	fi
}

##   usrsctp_build
##     Build usrsctp master in $HOME/tmp/usrsctp/
cmd_usrsctp_build() {
	# download
	USRSCTP_VER=master
	local zip=$USRSCTP_VER.zip
	local f=$ARCHIVE/usrsctp-$zip
	if test -r $f; then
		log "Already downloaded [$f]"
	else
		local url=https://github.com/sctplab/usrsctp
		curl -L $url/archive/refs/heads/$zip > $f
	fi

	# extract
	tmpdir=/tmp/$USER/usrsctp
	rm -r $tmpdir/*
	unzip -o -d $tmpdir $f
	mv $tmpdir/*/* $tmpdir

	# build
	cd $tmpdir
	./bootstrap
	./configure --prefix=/
	cd -
	DESTDIR=$HOME/tmp/usrsctp make -C $tmpdir install
}

##   mkimage [--tag=registry.nordix.org/cloud-native/sctp-test:latest]
##     Create the docker image and upload it to the local registry.
##
cmd_mkimage() {
	cmd_env
	mkdir -p $dir/image/default/bin
	make -C $dir/src clean
	make -j$(nproc) CFLAGS=-DSCTP_DEBUG -C $dir/src X=$dir/image/default/bin/usrsctpt static
	local imagesd=$($XCLUSTER ovld images)
	$imagesd/images.sh mkimage --force --upload --strip-host --tag=$__tag $dir/image
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
