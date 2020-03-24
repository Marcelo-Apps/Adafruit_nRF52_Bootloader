#******************************************************************************
# CONFIGURE
# - SDK_PATH    : path to SDK directory
#
# - SD_NAME     : e.g s132, s140
# - SD_VERSION : SoftDevice version e.g 6.0.0
# - SD_HEX      : to bootloader hex binary
#******************************************************************************

SDK_PATH     = lib/sdk/components
SDK11_PATH   = lib/sdk11/components
SD_PATH      = lib/softdevice/$(SD_FILENAME)

TUSB_PATH    = lib/tinyusb/src
NRFX_PATH    = lib/nrfx

SD_VERSION   = 6.1.1
SD_FILENAME  = $(SD_NAME)_nrf52_$(SD_VERSION)
SD_API_PATH  = $(SD_PATH)/$(SD_FILENAME)_API
SD_HEX       = $(SD_PATH)/$(SD_FILENAME)_softdevice.hex

# linker by MCU and SoftDevice eg. nrf52840_s140_v6.ld
LD_FILE      = linker/$(MCU_SUB_VARIANT)_$(SD_NAME)_v$(word 1, $(subst ., ,$(SD_VERSION))).ld

GIT_VERSION = $(shell git describe --dirty --always --tags)
GIT_SUBMODULE_VERSIONS = $(shell git submodule status | cut -d' ' -f3,4 | paste -s -d" " -)

# compiled file name
OUT_FILE = $(BOARD)_bootloader-$(GIT_VERSION)

# merged file = compiled + sd
MERGED_FILE = $(OUT_FILE)_$(SD_NAME)_$(SD_VERSION)

#******************************************************************************
# Tool configure
#******************************************************************************

# Toolchain commands
# Should be added to your PATH
CROSS_COMPILE = arm-none-eabi-
CC      := $(CROSS_COMPILE)gcc
AS      := $(CROSS_COMPILE)as
AR      := $(CROSS_COMPILE)ar -r
LD      := $(CROSS_COMPILE)ld
NM      := $(CROSS_COMPILE)nm
OBJDUMP := $(CROSS_COMPILE)objdump
OBJCOPY := $(CROSS_COMPILE)objcopy
SIZE    := $(CROSS_COMPILE)size
GDB     := $(CROSS_COMPILE)gdb

NRFUTIL = adafruit-nrfutil
NRFJPROG = nrfjprog

MK := mkdir -p
RM := rm -rf

# Verbose mode (V=). 0: default, 1: print out CFLAG, LDFLAG 2: print all compile command
ifeq ("$(V)","2")
	QUIET =
else
	QUIET = @
endif

# auto-detect BMP on macOS, otherwise have to specify
BMP_PORT ?= $(shell ls -1 /dev/cu.usbmodem????????1 | head -1)
GDB_BMP = $(GDB) -ex 'target extended-remote $(BMP_PORT)' -ex 'monitor swdp_scan' -ex 'attach 1'

#*********************************
# Select the board to build
#*********************************
BOARD_LIST = $(sort $(subst src/boards/,,$(wildcard src/boards/*)))

ifeq ($(filter $(BOARD),$(BOARD_LIST)),)
  $(info You must provide a BOARD parameter with 'BOARD='. Supported boards are:)
  $(info $(BOARD_LIST))
  $(error Invalid BOARD specified)
endif

# Build directory
BUILD = _build/build-$(BOARD)

# Board specific
-include src/boards/$(BOARD)/board.mk

# MCU_SUB_VARIANT can be nrf52 (nrf52832), nrf52833, nrf52840
ifeq ($(MCU_SUB_VARIANT),nrf52)
  SD_NAME = s132
  DFU_DEV_REV = 0xADAF
  MCU_FLAGS = -DNRF52 -DNRF52832_XXAA -DS132
else ifeq ($(MCU_SUB_VARIANT),nrf52833)
  SD_NAME = s140
  DFU_DEV_REV = 52840
  MCU_FLAGS = -DNRF52833_XXAA -DS140
else ifeq ($(MCU_SUB_VARIANT),nrf52840)
  SD_NAME = s140
  DFU_DEV_REV = 52840
  MCU_FLAGS = -DNRF52840_XXAA -DS140
else
  $(error Sub Variant $(MCU_SUB_VARIANT) is unknown)
endif

#******************************************************************************
# SOURCE FILES
#******************************************************************************

# all files in src
C_SRC += $(wildcard src/*.c)

# all sources files in specific board
C_SRC += $(wildcard src/boards/$(BOARD)/*.c)

# nrfx
C_SRC += $(NRFX_PATH)/drivers/src/nrfx_power.c
C_SRC += $(NRFX_PATH)/drivers/src/nrfx_nvmc.c
C_SRC += $(NRFX_PATH)/mdk/system_$(MCU_SUB_VARIANT).c

# SDK 11 files: serial + OTA DFU
C_SRC += $(SDK11_PATH)/libraries/bootloader_dfu/bootloader.c
C_SRC += $(SDK11_PATH)/libraries/bootloader_dfu/bootloader_settings.c
C_SRC += $(SDK11_PATH)/libraries/bootloader_dfu/bootloader_util.c
C_SRC += $(SDK11_PATH)/libraries/bootloader_dfu/dfu_transport_serial.c
C_SRC += $(SDK11_PATH)/libraries/bootloader_dfu/dfu_transport_ble.c
C_SRC += $(SDK11_PATH)/libraries/bootloader_dfu/dfu_single_bank.c

C_SRC += $(SDK11_PATH)/drivers_nrf/pstorage/pstorage_raw.c

C_SRC += $(SDK11_PATH)/ble/ble_services/ble_dfu/ble_dfu.c
C_SRC += $(SDK11_PATH)/ble/ble_services/ble_dis/ble_dis.c

# Latest SDK files: peripheral drivers
C_SRC += $(SDK_PATH)/libraries/timer/app_timer.c
C_SRC += $(SDK_PATH)/libraries/scheduler/app_scheduler.c
C_SRC += $(SDK_PATH)/libraries/util/app_error.c
C_SRC += $(SDK_PATH)/libraries/util/app_util_platform.c
C_SRC += $(SDK_PATH)/libraries/crc16/crc16.c
C_SRC += $(SDK_PATH)/libraries/hci/hci_mem_pool.c
C_SRC += $(SDK_PATH)/libraries/hci/hci_slip.c
C_SRC += $(SDK_PATH)/libraries/hci/hci_transport.c
C_SRC += $(SDK_PATH)/libraries/util/nrf_assert.c

# UART or USB Serial
ifeq ($(MCU_SUB_VARIANT),nrf52)
C_SRC += $(SDK_PATH)/libraries/uart/app_uart.c
C_SRC += $(SDK_PATH)/drivers_nrf/uart/nrf_drv_uart.c
C_SRC += $(SDK_PATH)/drivers_nrf/common/nrf_drv_common.c

IPATH += $(SDK11_PATH)/libraries/util
IPATH += $(SDK_PATH)/drivers_nrf/common
IPATH += $(SDK_PATH)/drivers_nrf/uart

else

# USB Application ( MSC + UF2 )
C_SRC += $(wildcard src/usb/*.c)
C_SRC += $(wildcard src/usb/uf2/*.c)

# TinyUSB stack
C_SRC += $(TUSB_PATH)/portable/nordic/nrf5x/dcd_nrf5x.c
C_SRC += $(TUSB_PATH)/common/tusb_fifo.c
C_SRC += $(TUSB_PATH)/device/usbd.c
C_SRC += $(TUSB_PATH)/device/usbd_control.c
C_SRC += $(TUSB_PATH)/class/cdc/cdc_device.c
C_SRC += $(TUSB_PATH)/class/msc/msc_device.c
C_SRC += $(TUSB_PATH)/tusb.c

endif


#******************************************************************************
# Assembly Files
#******************************************************************************
ASM_SRC = $(NRFX_PATH)/mdk/gcc_startup_$(MCU_SUB_VARIANT).S

#******************************************************************************
# INCLUDE PATH
#******************************************************************************

# src
IPATH += src
IPATH += src/boards/$(BOARD)

IPATH += src/cmsis/include
IPATH += src/usb
IPATH += src/boards
IPATH += $(TUSB_PATH)

# nrfx
IPATH += $(NRFX_PATH)
IPATH += $(NRFX_PATH)/mdk
IPATH += $(NRFX_PATH)/hal
IPATH += $(NRFX_PATH)/drivers/include
IPATH += $(NRFX_PATH)/drivers/src

IPATH += $(SDK11_PATH)/libraries/bootloader_dfu/hci_transport
IPATH += $(SDK11_PATH)/libraries/bootloader_dfu
IPATH += $(SDK11_PATH)/drivers_nrf/pstorage
IPATH += $(SDK11_PATH)/ble/common
IPATH += $(SDK11_PATH)/ble/ble_services/ble_dfu
IPATH += $(SDK11_PATH)/ble/ble_services/ble_dis

IPATH += $(SDK_PATH)/libraries/timer
IPATH += $(SDK_PATH)/libraries/scheduler
IPATH += $(SDK_PATH)/libraries/crc16
IPATH += $(SDK_PATH)/libraries/util
IPATH += $(SDK_PATH)/libraries/hci/config
IPATH += $(SDK_PATH)/libraries/uart
IPATH += $(SDK_PATH)/libraries/hci
IPATH += $(SDK_PATH)/drivers_nrf/delay

# Softdevice
IPATH += $(SD_API_PATH)/include
IPATH += $(SD_API_PATH)/include/nrf52

INC_PATHS = $(addprefix -I,$(IPATH))

#******************************************************************************
# Compiler Flags
# - Additional compiler flags
#******************************************************************************

#flags common to all targets
CFLAGS += -mcpu=cortex-m4
CFLAGS += -mthumb -mabi=aapcs --std=gnu99
CFLAGS += -Wall -Werror -Os -g3
CFLAGS += -mfloat-abi=hard -mfpu=fpv4-sp-d16

# keep every function in separate section. This will allow linker to dump unused functions
CFLAGS += -ffunction-sections -fdata-sections -fno-strict-aliasing
CFLAGS += -fno-builtin --short-enums -fstack-usage

# Defined Symbol (MACROS)
CFLAGS += -D__HEAP_SIZE=0
CFLAGS += -DCONFIG_GPIO_AS_PINRESET
CFLAGS += -DCONFIG_NFCT_PINS_AS_GPIOS
CFLAGS += -DSOFTDEVICE_PRESENT
CFLAGS += -DDFU_APP_DATA_RESERVED=7*4096
CFLAGS += $(MCU_FLAGS)

CFLAGS += -DUF2_VERSION='"$(GIT_VERSION) $(GIT_SUBMODULE_VERSIONS) $(SD_NAME) $(SD_VERSION)"'
CFLAGS += -DBLEDIS_FW_VERSION='"$(GIT_VERSION) $(SD_NAME) $(SD_VERSION)"'

_VER = $(subst ., ,$(word 1, $(subst -, ,$(GIT_VERSION))))
CFLAGS += -DMK_BOOTLOADER_VERSION='($(word 1,$(_VER)) << 16) + ($(word 2,$(_VER)) << 8) + $(word 3,$(_VER))'


#******************************************************************************
# Linker Flags
#
#******************************************************************************

# keep every function in separate section. This will allow linker to dump unused functions
LDFLAGS += -Xlinker -Map=$(BUILD)/$(OUT_FILE).map
LDFLAGS += -mthumb -mabi=aapcs -Llinker -T$(LD_FILE)
LDFLAGS += -mcpu=cortex-m4
LDFLAGS += -mfloat-abi=hard -mfpu=fpv4-sp-d16

# let linker to dump unused sections
LDFLAGS += -Wl,--gc-sections

# use newlib in nano version
LDFLAGS += --specs=nano.specs -lc -lnosys

#******************************************************************************
# Assembler flags
#
#******************************************************************************
ASMFLAGS += -x assembler-with-cpp
ASMFLAGS += -D__HEAP_SIZE=0
ASMFLAGS += -DSOFTDEVICE_PRESENT
ASMFLAGS += $(MCU_FLAGS)


#function for removing duplicates in a list
remduplicates = $(strip $(if $1,$(firstword $1) $(call remduplicates,$(filter-out $(firstword $1),$1))))

C_SOURCE_FILE_NAMES = $(notdir $(C_SRC))
C_PATHS = $(call remduplicates, $(dir $(C_SRC) ) )
C_OBJECTS = $(addprefix $(BUILD)/, $(C_SOURCE_FILE_NAMES:.c=.o) )

ASM_SOURCE_FILE_NAMES = $(notdir $(ASM_SRC))
ASM_PATHS = $(call remduplicates, $(dir $(ASM_SRC) ))
ASM_OBJECTS = $(addprefix $(BUILD)/, $(ASM_SOURCE_FILE_NAMES:.S=.o) )

vpath %.c $(C_PATHS)
vpath %.S $(ASM_PATHS)

OBJECTS = $(C_OBJECTS) $(ASM_OBJECTS)

#******************************************************************************
# BUILD TARGETS
#******************************************************************************

ifeq ("$(V)","1")
$(info CFLAGS   $(CFLAGS))
$(info )
$(info LDFLAGS  $(LDFLAGS))
$(info )
$(info ASMFLAGS $(ASMFLAGS))
$(info )
endif

.phony: all clean size flash sd erase

# default target to build
all: $(BUILD)/$(OUT_FILE)-nosd.out size

#******************* Flash target *******************

check_defined = \
    $(strip $(foreach 1,$1, \
    $(call __check_defined,$1,$(strip $(value 2)))))
__check_defined = \
    $(if $(value $1),, \
    $(error Undefined make flag: $1$(if $2, ($2))))

# Flash the compiled
flash: $(BUILD)/$(OUT_FILE)-nosd.hex
	@echo Flashing: $<
	$(NRFJPROG) --program $< --sectoranduicrerase -f nrf52 --reset

dfu-flash: $(BUILD)/$(MERGED_FILE).zip
	@:$(call check_defined, SERIAL, example: SERIAL=/dev/ttyACM0)
	$(NRFUTIL) --verbose dfu serial --package $< -p $(SERIAL) -b 115200 --singlebank --touch 1200

sd:
	@echo Flashing: $(SD_HEX)
	$(NRFJPROG) --program $(SD_HEX) -f nrf52 --chiperase  --reset

erase:
	@echo Erasing chip
	$(NRFJPROG) --eraseall -f nrf52

gdbflash: $(BUILD)/$(MERGED_FILE).hex
	@echo Flashing: $<
	@$(GDB_BMP) -nx --batch -ex 'load $<' -ex 'compare-sections' -ex 'kill'

gdb: $(BUILD)/$(OUT_FILE)-nosd.out
	$(GDB_BMP) $<

#******************* Compile rules *******************

## Create build directories
$(BUILD):
	@$(MK) $@

clean:
	@$(RM) $(BUILD)

# Create objects from C SRC files
$(BUILD)/%.o: %.c
	@echo CC $(notdir $<)
	$(QUIET)$(CC) $(CFLAGS) $(INC_PATHS) -c -o $@ $<

# Assemble files
$(BUILD)/%.o: %.S
	@echo AS $(notdir $<)
	$(QUIET)$(CC) $(ASMFLAGS) $(INC_PATHS) -c -o $@ $<

# Link
$(BUILD)/$(OUT_FILE)-nosd.out: $(BUILD) $(OBJECTS)
	@echo LD $(OUT_FILE)-nosd.out
	$(QUIET)$(CC) $(LDFLAGS) $(OBJECTS) $(LIBS) -lm -o $@

size: $(BUILD)/$(OUT_FILE)-nosd.out
	-@echo ''
	$(QUIET)$(SIZE) $<
	-@echo ''


#******************* Binary generator *******************
.phony: genhex genpkg

## Create binary .hex file from the .out file
genhex: $(BUILD)/$(OUT_FILE)-nosd.hex

$(BUILD)/$(OUT_FILE)-nosd.hex: $(BUILD)/$(OUT_FILE)-nosd.out
	@echo CR $(OUT_FILE)-nosd.hex
	$(QUIET)$(OBJCOPY) -O ihex $< $@

# merge bootloader and sd hex together
combinehex: $(BUILD)/$(MERGED_FILE).hex

$(BUILD)/$(MERGED_FILE).hex: $(BUILD)/$(OUT_FILE)-nosd.hex
	@echo CR $(MERGED_FILE).hex
	@mergehex -q -m $< $(SD_HEX) -o $@

## Create pkg file for bootloader+SD combo to use with DFU
genpkg: $(BUILD)/$(MERGED_FILE).zip

$(BUILD)/$(MERGED_FILE).zip: $(BUILD)/$(OUT_FILE)-nosd.hex
	@$(NRFUTIL) dfu genpkg --dev-type 0x0052 --dev-revision $(DFU_DEV_REV) --bootloader $< --softdevice $(SD_HEX) $@
