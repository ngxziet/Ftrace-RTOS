#!/bin/bash

TRACE_DIR=/sys/kernel/debug/tracing
LOG_FILE=/tmp/ftrace_buffer.log

if [ "$(id -u)" -ne 0 ]; then
  echo "⚠️  Vui lòng chạy script với sudo"
  exit 1
fi

reset_ftrace() {
  echo 0 > $TRACE_DIR/tracing_on
  echo > $TRACE_DIR/trace
  echo nop > $TRACE_DIR/current_tracer
  echo > $TRACE_DIR/set_ftrace_pid
  echo > $TRACE_DIR/set_event
}

start_ftrace() {
  reset_ftrace
  echo sys_enter_openat > $TRACE_DIR/set_event
  echo 1 > $TRACE_DIR/events/syscalls/sys_enter_openat/enable
  echo 1 > $TRACE_DIR/tracing_on
}

RUNNING=1

start_ftrace

echo "▶️ Đang ghi ftrace realtime (sys_enter_openat)..."
echo "Nhấn 'p' + Enter để tạm dừng và lọc log theo PID,"
echo "Nhấn 'q' + Enter để thoát."
echo "Nhấn Enter để tiếp tục nếu đang tạm dừng."

FIFO=/tmp/ftrace_fifo
[[ -p $FIFO ]] || mkfifo $FIFO

cat $TRACE_DIR/trace_pipe > $FIFO &
CAT_PID=$!

tee $LOG_FILE < $FIFO > /dev/null &
TEE_PID=$!

while [ $RUNNING -eq 1 ]; do
  read -r -t 1 input

  if [ "$input" = "p" ]; then
    echo -e "\n⏸ Đã tạm dừng ftrace ghi log."
    kill $CAT_PID $TEE_PID

    echo -n "🔢 Nhập PID cần lọc: "
    read PID_FILTER

    if [[ ! "$PID_FILTER" =~ ^[0-9]+$ ]]; then
      echo "❌ PID không hợp lệ, tiếp tục ghi..."
      start_ftrace
      cat $TRACE_DIR/trace_pipe > $FIFO &
      CAT_PID=$!
      tee $LOG_FILE < $FIFO > /dev/null &
      TEE_PID=$!
      continue
    fi

    echo "📂 Hiển thị log đã lọc theo PID: $PID_FILTER"
    grep --color=always -E "\-$PID_FILTER\b" $LOG_FILE

    echo -e "\n▶️ Nhấn 'p' + Enter để tạm dừng, 'q' + Enter để thoát, hoặc Enter để tiếp tục ghi log."
    read -r cmd

    if [ "$cmd" = "q" ]; then
      RUNNING=0
    elif [ "$cmd" = "" ]; then
      start_ftrace
      cat $TRACE_DIR/trace_pipe > $FIFO &
      CAT_PID=$!
      tee $LOG_FILE < $FIFO > /dev/null &
      TEE_PID=$!
    else
      echo "Lệnh không hợp lệ, tiếp tục ghi..."
      start_ftrace
      cat $TRACE_DIR/trace_pipe > $FIFO &
      CAT_PID=$!
      tee $LOG_FILE < $FIFO > /dev/null &
      TEE_PID=$!
    fi

  elif [ "$input" = "q" ]; then
    RUNNING=0
  fi
done

kill $CAT_PID $TEE_PID 2>/dev/null
rm -f $FIFO
echo "⏹ Đã dừng và thoát."
