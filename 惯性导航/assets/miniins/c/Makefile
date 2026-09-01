# Mini-INS C 移植版 Makefile（主机端 gcc，D0-D3 用；上板时换 arm-none-eabi / Keil）
#
#   make           用 double 构建三个对拍程序（默认）
#   make float     用 float 构建（验证单精度允差）
#   make clean     清理
#
# 构建产物在 build/（gitignore 之外请自行清理，或 make clean）

CC      ?= gcc
CFLAGS  ?= -std=c99 -O2 -Wall -Wextra -Iinclude
SRCS    := src/ins_math.c src/triad.c src/mahony.c
BUILD   := build
EXES    := $(BUILD)/test_trans.exe $(BUILD)/test_triad.exe $(BUILD)/test_mahony.exe

.PHONY: all float clean
all: $(EXES)

float: CFLAGS += -DINS_REAL=float
float: clean
	$(MAKE) all CFLAGS="$(CFLAGS)"

$(BUILD):
	mkdir -p $(BUILD)

$(BUILD)/test_trans.exe: tests/test_trans.c $(SRCS) | $(BUILD)
	$(CC) $(CFLAGS) $< $(SRCS) -o $@ -lm

$(BUILD)/test_triad.exe: tests/test_triad.c $(SRCS) | $(BUILD)
	$(CC) $(CFLAGS) $< $(SRCS) -o $@ -lm

$(BUILD)/test_mahony.exe: tests/test_mahony.c $(SRCS) | $(BUILD)
	$(CC) $(CFLAGS) $< $(SRCS) -o $@ -lm

clean:
	rm -rf $(BUILD)
