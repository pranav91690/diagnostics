#!/bin/bash

VERSION=1.0
RELEASE_MONTH="Sept 2020"

getScriptDir() {

    #get script directory
    SOURCE="${BASH_SOURCE[0]}"
    while [ -h "$SOURCE" ]; do # resolve $SOURCE until the file is no longer a symlink
        DIR="$(cd -P "$(dirname "$SOURCE")" >/dev/null 2>&1 && pwd)"
        SOURCE="$(readlink "$SOURCE")"
        [[ $SOURCE != /* ]] && SOURCE="$DIR/$SOURCE" # if $SOURCE was a relative symlink, we need to resolve it relative to the path where the symlink file was located
    done
    PROP_DIR="$(cd -P "$(dirname "$SOURCE")" >/dev/null 2>&1 && pwd)"

    #validate args.prop
    FILE=args.prop
    if [ -f "$PROP_DIR/$FILE" ]; then
        echo "Using props file $PROP_DIR/$FILE"
    else
        echo "$FILE does not exist in $PROP_DIR. Exiting..."
        exit 1
    fi

}
getProperty() {
    prop_value=""
    prop_key=$1
    prop_value=$(cat args.prop | grep ${prop_key} | awk -F '[=]' '{print $2}' | awk '{$1=$1;print}')
}

getoutputdir() {

    echo "$(ts) Reading Output Dir from props file... "
    key="OUTPUTDIR"
    getProperty ${key}
    echo "$(ts) Key = OUTPUTDIR ; Value = " ${prop_value}

    if [ -n "$prop_value" ]; then
        OUTPUTDIR=$prop_value
    else
        echo "$(ts) OUTPUTDIR not provided, default output will be in current working directory of run.sh "
    fi
}

findNODEPID() {
    NODEPID=($(ps -ef | grep tomcat | grep -v grep | awk '{ print $2 }'))
    if [ -n "$NODEPID" ]; then
        echo "$(ts) Node process ID is " ${NODEPID}
    else
        echo "$(ts) No node process is running"
        exit 1
    fi
}

getInterval() {
    echo "$(ts) Reading INTERVAL name from props file... "
    key="INTERVAL"
    getProperty ${key}
    echo "$(ts) Key = INTERVAL; Value = " ${prop_value}
    if [ -n "$prop_value" ]; then
        INTERVAL=${prop_value}
    else
        echo "$(ts) Interval to collect diagnostics is empty, default is 30 sec"
        INTERVAL=30
    fi

    if [ ${INTERVAL} -lt 30 ]; then
        INTERVAL=30
    fi
}

getIteration() {
    echo "$(ts) Reading ITERATION name from props file... "
    key="ITERATION"
    getProperty ${key}
    echo "$(ts) Key = ITERATION; Value = " ${prop_value}
    if [ -n "$prop_value" ]; then
        ITERATION=${prop_value}
    else
        echo "$(ts) Iteration to collect stacks is empty, default is 3"
        ITERATION=3
    fi

}

collecttop() {
    PIDS=("$@")
    myiter=$i

    for MYPID in "${PIDS[@]}"; do
        echo "$(ts) Collecting top on PID " ${MYPID}
        if [ -n "$MYPID" ]; then
            FILENAME=${CURRENT_DIR}/top.${MYPID}_${myiter}.out
            top -b -n 1 -H -p $MYPID >${FILENAME} &
        fi
    done
}

collectheap() {
    PIDS=("$@")
    myiter=$i

    for MYPID in "${PIDS[@]}"; do
        if [ -n "$MYPID" ]; then
            FILENAME=$CURRENT_DIR/java_heap$MYPID.bin
            echo "$(ts) Collecting java heap on PID " ${MYPID}
            $JAVA_HOME/bin/jcmd $MYPID GC.heap_dump $FILENAME
        fi
    done
}

collectpstack() {
    PIDS=("$@")
    PSTACK_COMMAND=pstack
    myiter=$i
    for MYPID in "${PIDS[@]}"; do
        if [ -n "$MYPID" ]; then
            $PSTACK_COMMAND $MYPID >$CURRENT_DIR/pstack.${MYPID}_${myiter}.out
        fi
    done
}

collectjstack() {
    PIDS=("$@")
    myiter=$i

    for MYPID in "${PIDS[@]}"; do

        if [ -n "$MYPID" ]; then
            echo "$(ts) Collecting java thread stack  on PID " ${MYPID}

            FILENAME=${CURRENT_DIR}/jstack.${MYPID}_${myiter}.out

            $JAVA_HOME/bin/jcmd $MYPID Thread.print >$FILENAME
            if [ $? -eq 0 ]; then
                echo "$(ts) jcmd threads collected."
            else
                echo "$(ts) collecting java stack with jstack -F for PID : " ${MYPID}
                $JAVA_HONE/bin/ jstack -F $MYPID >$FILENAME
            fi
        fi
    done
}

collectstrace() {

    PIDS=("$@")
    myiter=$i
    STIMEOUT="$(($INTERVAL - 2))"
    for MYPID in "${PIDS[@]}"; do
        if [ -n "$MYPID" ]; then
            echo "$(ts) Collecting strace on PID ${MYPID}  for $STIMEOUT seconds"

            FILENAME=${CURRENT_DIR}/strace.${MYPID}_${myiter}.out
            timeout $STIMEOUT strace -tT -fF -o $FILENAME -p $MYPID >/dev/null 2>&1 &
        fi
    done

}

collectnetstat() {

    PIDS=("$@")
    myiter=$i
    for MYPID in "${PIDS[@]}"; do
        echo "$(ts) Collecting netstat on PID "${MYPID}
        if [ -n "$MYPID" ]; then
            FILENAME=${CURRENT_DIR}/netstat.${MYPID}_${myiter}.out
            netstat -peano | grep $MYPID >$FILENAME &
        fi
    done
}

collectlsof() {

    PIDS=("$@")
    myiter=$i
    for MYPID in "${PIDS[@]}"; do
        echo "$(ts) Collecting lsof on PID " ${MYPID}
        if [ -n "$MYPID" ]; then
            FILENAME=${CURRENT_DIR}/lsof.${MYPID}_${myiter}.out
            lsof -p $MYPID >$FILENAME &
        fi

    done
}

ts() {
    date +"%Y-%m-%d %H:%M:%S,%3N"
}

#Main Loop
main() {
    getScriptDir
    getoutputdir

    OUTPUT_PREFIX=$(hostname)
    CMD_CURRENT_HR_MIN=$(date +%Y-%m-%d_%H_%M)

    if [ -n "${OUTPUTDIR}" ]; then
        CURRENT_DIR="${OUTPUTDIR}/${OUTPUT_PREFIX}_${CMD_CURRENT_HR_MIN}"
    else
        CURRENT_DIR="${PWD}/${OUTPUT_PREFIX}_${CMD_CURRENT_HR_MIN}"
    fi

    echo "Output dir set for diagnostics collection and main log : ${CURRENT_DIR}"

    mkdir -p $CURRENT_DIR

    SCRIPTLOG="${CURRENT_DIR}/mainlog.log"
    exec > >(tee -i $SCRIPTLOG)
    exec 2>&1

    echo "$(ts) ${VERSION}"
    echo "$(ts) ${RELEASE_MONTH}"
    echo "$(ts) Starting!"
    echo "$(ts) Output dir set for diagnostics collection and main log : ${CURRENT_DIR}"

    findNODEPID
    getInterval
    getIteration

    i=1
    while [ $i -le $ITERATION ]; do

        echo "$(ts) Iteration : " $i
        collectjstack $NODEPID
        collectpstack $NODEPID
        collectstrace $NODEPID
        collectnetstat $NODEPID
        collectlsof $NODEPID
        collecttop $NODEPID

        if [ $i -lt $ITERATION ]; then
            echo "$(ts) Sleeping..."
            sleep $INTERVAL
            echo "$(ts) Woke up..."
            #check if PIDs changed
            echo "$(ts) Refreshing PIDs.. "
            findNODEPID
        fi
        ((i++))

    done

    collectheap $NODEPID

    #create directory for ISPLOGS

    #archive
    file_name="logs"
    current_time=$(date "+%Y.%m.%d-%H.%M.%S")
    tarfilename=$file_name.$current_time.tar.gz
    tar --remove-files -zcf $CURRENT_DIR/$tarfilename $CURRENT_DIR/*
}
main
echo "$(ts) Completed diagnostics collection. Please share this output tar file : " $CURRENT_DIR/$tarfilename
exit 0
