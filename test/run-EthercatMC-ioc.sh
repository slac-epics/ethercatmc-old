#!/bin/sh
APPXX=EthercatMC
TOP=$(echo $PWD/.. | sed -e "s%/test/\.\.$%%")
export APPXX
EPICS_EEE=n

uname_s=$(uname -s 2>/dev/null || echo unknown)
uname_m=$(uname -m 2>/dev/null || echo unknown)

INSTALLED_EPICS=../../../../.epics.$(hostname).$uname_s.$uname_m

if test "$EPICS_ENV_PATH" &&
    test "$EPICS_MODULES_PATH" &&
    test "$EPICS_BASES_PATH"; then
  EPICS_EEE=y
elif test -r $INSTALLED_EPICS; then
  echo INSTALLED_EPICS=$INSTALLED_EPICS
 . $INSTALLED_EPICS
else
  echo not found: INSTALLED_EPICS=$INSTALLED_EPICS
fi
export EPICS_EEE
echo EPICS_EEE=$EPICS_EEE

if test -z "$EPICS_BASE";then
  echo >&2 "EPICS_BASE" is not set
  exit 1
fi

MOTORCFG="$1"
export MOTORCFG
echo MOTORCFG=$MOTORCFG
(
  cd startup &&
  if ! test -f st.${MOTORCFG}.cmd; then
    CMDS=$(echo st.*.cmd | sed -e "s/st\.//g" -e "s/\.cmd//g")
    #echo CMDS=$CMDS
    test -n "$1" && echo >&2 "not found st.${1}.cmd"
    echo >&2 "try one of these:"
    for cmd in $CMDS; do
      echo >&2 $0 " $cmd" " <ip>[:port]"
    done
    exit 1
  fi
) || exit 1

shift

MOTORIP=127.0.0.1
MOTORPORT=5000

if test -n "$1"; then
  # allow doit.sh host:port
  PORT=${1##*:}
  HOST=${1%:*}
  echo HOST=$HOST PORT=$PORT
  if test "$PORT" != "$HOST"; then
    MOTORPORT=$PORT
  fi
  echo HOST=$HOST MOTORPORT=$MOTORPORT
  MOTORIP=$HOST
  echo MOTORIP=$MOTORIP
fi
export MOTORIP MOTORPORT
(
  IOCDIR=../iocBoot/ioc${APPXX}
  DBMOTOR=db
  envPathsdst=./envPaths.$EPICS_HOST_ARCH &&
  stcmddst=./st.cmd.$EPICS_HOST_ARCH &&
  mkdir -p  $IOCDIR/ &&
  if test "x$EPICS_EEE" = "xn"; then
    if test -d ../motor; then
      DBMOTOR=dbmotor
      #motor
      (cd ../motor && make install) && (cd .. && make install) || {
        echo >&2 make install failed
        exit 1
        }
      (cd .. &&
          mkdir -p dbmotor &&
          for src in db/*template; do
            dst=dbmotor/${src##*/}
            echo sed PWD=$PWD src=$src dst=$dst
            sed <"$src" >"$dst" \
                -e "s%record(axis%record(motor%" \
                -e "s%asynAxis%asynMotor%"
          done
      )
    fi &&
    (cd ../../motor &&
     make install) || {
       echo >&2 make install failed
       exit 1
    }
    (cd .. &&
     make install) || {
       echo >&2 make install failed
       exit 1
    }

  else
    #EEE
    if sed -e "s/#.*//" -e "s/-ESS\$//"  <startup/st.${MOTORCFG}.cmd |
        grep "require *motor,.*[A-Za-z]"; then
      (cd ../../motor &&
         rm -rfv ./dbd ./include ./doc ./db &&
         make install) || {
         echo >&2 make install failed
         exit 1
      }
    fi &&
    if sed -e "s/#.*//" <startup/st.${MOTORCFG}.cmd |
        grep "require *EthercatMC,.*[A-Za-z]"; then
      (cd .. &&
         rm -rfv ./dbd ./include ./doc ./db &&
         make install) || {
         echo >&2 make install failed
         exit 1
      }
    fi
  fi &&
  cd $IOCDIR/ &&
  if test "x$EPICS_EEE" = "xy"; then
    #EEE
    stcmddst=./st.cmd.EEE.$EPICS_HOST_ARCH &&
    # We need to patch the cmd files to adjust "<"
    # All patched files are under IOCDIR=../iocBoot/ioc${APPXX}
    for src in  ../../startup/*cmd ../../test/startup/*cfg ../../test/startup/*cmd; do
      dst=${src##*/}
      echo cp PWD=$PWD src=$src dst=$dst
      cp "$src" "$dst"
    done &&
    rm -f $stcmddst &&
    sed  <st.${MOTORCFG}.cmd  \
      -e "s/require motor,USER/require motor,$USER/" \
      -e "s/require EthercatMC,USER/require EthercatMC,$USER/" \
      -e "s/^cd /#cd /" \
      -e "s/127.0.0.1/$MOTORIP/" \
      -e "s/5000/$MOTORPORT/" |
    grep -v '^  *#' >$stcmddst || {
      echo >&2 can not create stcmddst $stcmddst
      exit 1
    }
    rm -fv  require.lock* &&
    chmod +x $stcmddst &&
    cmd=$(echo iocsh $stcmddst) &&
    echo PWD=$PWD cmd=$cmd &&
    eval $cmd
  else
    # classic EPICS, non EEE
    # We need to patch the cmd files to adjust dbLoadRecords
    # All patched files are under IOCDIR=../iocBoot/ioc${APPXX}
    for src in ../../test/startup/*cmd  ../../startup/*cmd; do
      dst=${src##*/}
      echo sed PWD=$PWD src=$src dst=$dst
      sed <"$src" >"$dst" \
        -e "s%dbLoadRecords(\"%dbLoadRecords(\"./$DBMOTOR/%" \
        -e "s%adsAsynPortDriverConfigure%#adsAsynPortDriverConfigure%"
    done &&
    rm -f $stcmddst &&
    cat >$stcmddst <<-EOF &&
#!../../bin/$EPICS_HOST_ARCH/${APPXX}
#This file is autogenerated by run-EthercatMC-ioc.sh - do not edit
epicsEnvSet("ARCH","$EPICS_HOST_ARCH")
epicsEnvSet("IOC","ioc${APPXX}")
epicsEnvSet("TOP","$TOP")
epicsEnvSet("EPICS_BASE","$EPICS_BASE")

cd ${TOP}
dbLoadDatabase "dbd/${APPXX}.dbd"
${APPXX}_registerRecordDeviceDriver pdbbase
EOF
   # Side note: st.${MOTORCFG}.cmd needs extra patching
   echo sed PWD=$PWD "<../../startup/st.${MOTORCFG}.cmd >>$stcmddst"
   sed <../../test/startup/st.${MOTORCFG}.cmd  \
      -e "s/__EPICS_HOST_ARCH/$EPICS_HOST_ARCH/" \
      -e "s/5000/$MOTORPORT/" \
      -e "s/127.0.0.1/$MOTORIP/" \
      -e "s%cfgFile=./%cfgFile=./test/startup/%"    \
      -e "s%< %< ${TOP}/iocBoot/ioc${APPXX}/%"    \
      -e "s%require%#require%" \
      | grep -v '^  *#' >>$stcmddst &&
    cat >>$stcmddst <<-EOF &&
    iocInit
EOF
    chmod +x $stcmddst &&
    egrep -v "^ *#" $stcmddst >xx
    echo PWD=$PWD $stcmddst
    $stcmddst
  fi
)
