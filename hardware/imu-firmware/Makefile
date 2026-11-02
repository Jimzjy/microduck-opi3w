# GCC build for the imu_to_dxl STM32G031F8P6 firmware.
#
# The upstream project builds with Keil armclang (see Tools/build.ps1 and
# MDK-ARM/imu_to_dxl.sct). This Makefile reproduces the same image with the
# open source arm-none-eabi toolchain.

TOOLCHAIN ?= arm-none-eabi-
CC        := $(TOOLCHAIN)gcc
OBJCOPY   := $(TOOLCHAIN)objcopy
SIZE      := $(TOOLCHAIN)size

BUILD ?= Build-gcc
TARGET := $(BUILD)/imu_to_dxl

CPU     := -mcpu=cortex-m0plus -mthumb -mfloat-abi=soft
DEFS    := -DSTM32G031xx -DHSE_VALUE=16000000
INCLUDES := -ICore/Inc \
            -IDrivers/CMSIS/Include \
            -IDrivers/CMSIS/Device/ST/STM32G0xx/Include \
            -IDrivers/LSM6DSV16X
CFLAGS  := $(CPU) $(DEFS) $(INCLUDES) \
           -std=c11 -Oz -g -gdwarf-4 \
           -ffunction-sections -fdata-sections -fshort-enums \
           -Wall -Wextra -Wno-unused-parameter
LDFLAGS := $(CPU) -T gcc/link.ld \
           -Wl,--gc-sections -Wl,-Map=$(TARGET).map,--cref \
           -specs=nano.specs -specs=nosys.specs

SRC := Core/Src/main.c \
       Core/Src/board.c \
       Core/Src/control_table.c \
       Core/Src/imu.c \
       Core/Src/protocol.c \
       Drivers/LSM6DSV16X/lsm6dsv16x_reg.c \
       Drivers/CMSIS/Device/ST/STM32G0xx/Source/system_stm32g0xx.c \
       gcc/startup_gcc.c

OBJ := $(addprefix $(BUILD)/,$(notdir $(SRC:.c=.o)))
vpath %.c $(sort $(dir $(SRC)))

.PHONY: all clean size

all: $(TARGET).hex $(TARGET).bin size

$(BUILD):
	mkdir -p $(BUILD)

$(BUILD)/%.o: %.c | $(BUILD)
	$(CC) $(CFLAGS) -c $< -o $@

$(TARGET).elf: $(OBJ) gcc/link.ld
	$(CC) $(OBJ) $(LDFLAGS) -o $@

$(TARGET).hex: $(TARGET).elf
	$(OBJCOPY) -O ihex $< $@

$(TARGET).bin: $(TARGET).elf
	$(OBJCOPY) -O binary $< $@

size: $(TARGET).elf
	$(SIZE) $(TARGET).elf

clean:
	rm -rf $(BUILD)
