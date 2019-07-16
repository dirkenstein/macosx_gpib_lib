/*
 * Copyright (c) 2004 Frank Mori Hess (fmhess@users.sourceforge.net)
 * Copyright (c) 2018 Guilhem Vavelin (guileukow@users.sourceforge.net)
 *
 *    This source code is free software; you can redistribute it
 *    and/or modify it in source code form under the terms of the GNU
 *    General Public License as published by the Free Software
 *    Foundation; either version 2 of the License, or (at your option)
 *    any later version.
 *
 *    This program is distributed in the hope that it will be useful,
 *    but WITHOUT ANY WARRANTY; without even the implied warranty of
 *    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 *    GNU General Public License for more details.
 *
 *    You should have received a copy of the GNU General Public License
 *    along with this program; if not, write to the Free Software
 *    Foundation, Inc., 59 Temple Place - Suite 330, Boston, MA 02111-1307, USA
 */

#import "gpib_board.h"
#import "tms9914.h"
#import <mach/mach.h>
#import <IOKit/usb/IOUSBLib.h>
#import <pthread.h>
#import <semaphore.h>

#define USB_TYPE_STANDARD		(0x00 << 5)
#define USB_TYPE_CLASS			(0x01 << 5)
#define USB_TYPE_VENDOR			(0x02 << 5)
#define USB_TYPE_RESERVED		(0x03 << 5)

#define USB_RECIP_DEVICE		0x00
#define USB_RECIP_INTERFACE		0x01
#define USB_RECIP_ENDPOINT		0x02
#define USB_RECIP_OTHER	0x03

#define USB_DIR_IN 0x80

enum usb_vendor_ids
{
    USB_VENDOR_ID_AGILENT = 0x0957
};

enum usb_device_ids
{
    USB_DEVICE_ID_AGILENT_82357A = 0x0107,
    USB_DEVICE_ID_AGILENT_82357A_PREINIT = 0x0007,	// device id before firmware is loaded
    USB_DEVICE_ID_AGILENT_82357B = 0x0718,	// device id before firmware is loaded
    USB_DEVICE_ID_AGILENT_82357B_PREINIT = 0x0518,	// device id before firmware is loaded
};

enum endpoint_addresses
{
    AGILENT_82357_CONTROL_ENDPOINT = 0x0,
    AGILENT_82357_BULK_IN_ENDPOINT = 2,
    AGILENT_82357A_BULK_OUT_ENDPOINT = 1,
    AGILENT_82357A_INTERRUPT_IN_ENDPOINT = 3,
    AGILENT_82357B_BULK_OUT_ENDPOINT = 0x6,
    AGILENT_82357B_INTERRUPT_IN_ENDPOINT = 0x88,
};

enum bulk_commands
{
    DATA_PIPE_CMD_WRITE = 0x1,
    DATA_PIPE_CMD_READ = 0x3,
    DATA_PIPE_CMD_WR_REGS = 0x4,
    DATA_PIPE_CMD_RD_REGS = 0x5
};

enum agilent_82357a_read_flags
{
    ARF_END_ON_EOI = 0x1,
    ARF_NO_ADDRESS = 0x2,
    ARF_END_ON_EOS_CHAR = 0x4,
    ARF_SPOLL = 0x8
};

enum agilent_82357a_trailing_read_flags
{
    ATRF_EOI = 0x1,
    ATRF_ATN = 0x2,
    ATRF_IFC = 0x4,
    ATRF_EOS = 0x8,
    ATRF_ABORT = 0x10,
    ATRF_COUNT = 0x20,
    ATRF_DEAD_BUS = 0x40,
    ATRF_UNADDRESSED = 0x80
};

enum agilent_82357a_write_flags
{
    AWF_SEND_EOI = 0x1,
    AWF_NO_FAST_TALKER_FIRST_BYTE = 0x2,
    AWF_NO_FAST_TALKER = 0x4,
    AWF_NO_ADDRESS = 0x8,
    AWF_ATN = 0x10,
    AWF_SEPARATE_HEADER = 0x80
};

enum agilent_82357a_interrupt_flag_bit_numbers
{
    AIF_SRQ_BN = 0,
    AIF_WRITE_COMPLETE_BN = 1,
    AIF_READ_COMPLETE_BN = 2,
};

enum agilent_82357_error_codes
{
    UGP_SUCCESS = 0,
    UGP_ERR_INVALID_CMD = 1,
    UGP_ERR_INVALID_PARAM = 2,
    UGP_ERR_INVALID_REG = 3,
    UGP_ERR_GPIB_READ = 4,
    UGP_ERR_GPIB_WRITE = 5,
    UGP_ERR_FLUSHING = 6,
    UGP_ERR_FLUSHING_ALREADY = 7,
    UGP_ERR_UNSUPPORTED = 8,
    UGP_ERR_OTHER  = 9
};

enum agilent_82357_control_values
{
    XFER_ABORT = 0xa0,
    XFER_STATUS = 0xb0,
};

enum xfer_status_bits
{
    XS_COMPLETED = 0x1,
    XS_READ = 0x2,
};

enum xfer_status_completion_bits
{
    XSC_EOI = 0x1,
    XSC_ATN = 0x2,
    XSC_IFC = 0x4,
    XSC_EOS = 0x8,
    XSC_ABORT = 0x10,
    XSC_COUNT = 0x20,
    XSC_DEAD_BUS = 0x40,
    XSC_BUS_NOT_ADDRESSED = 0x80
};

enum xfer_abort_type
{
    XA_FLUSH = 0x1
};

typedef struct {
    BOOL timed_out;
    IOReturn result;
    UInt32 actual_length;
    BOOL triggered;
    CFRunLoopRef runner;
    CFRunLoopSourceRef complete;
}bulk_context;

typedef struct
{
    UInt32 interrupt_flags;
    UInt32* interrupt_buffer;
    IOUSBInterfaceInterface300** bus_interface;
    UInt32 bulk_out_endpoint;
    UInt32 bulk_in_endpoint;
    UInt32 interrupt_in_endpoint;
    UInt16 maxInOutPacketSize;
    UInt16 maxInterruptPacketSize;
    BOOL triggered;
    private_board *board;
}private_data;

struct register_pairlet
{
    short address;
    unsigned short value;
};

enum firmware_registers
{
    HW_CONTROL = 0xa,
    LED_CONTROL = 0xb,
    RESET_TO_POWERUP = 0xc,
    PROTOCOL_CONTROL = 0xd,
    FAST_TALKER_T1 = 0xe
};

enum hardware_control_bits
{
    NOT_TI_RESET = 0x1,
    SYSTEM_CONTROLLER = 0x2,
    NOT_PARALLEL_POLL = 0x4,
    OSCILLATOR_5V_ON = 0x8,
    OUTPUT_5V_ON = 0x20,
    CPLD_3V_ON = 0x80,
};

enum led_control_bits
{
    FIRMWARE_LED_CONTROL = 0x1,
    FAIL_LED_ON = 0x20,
    READY_LED_ON = 0x40,
    ACCESS_LED_ON = 0x80
};

enum reset_to_powerup_bits
{
    RESET_SPACEBALL = 0x1,	// wait 2 millisec after sending
};

enum protocol_control_bits
{
    WRITE_COMPLETE_INTERRUPT_EN = 0x1,
};

static const UInt16 control_request = 0x4;

/*! \category agilent_82357_ab(gpib_board)
    \abstract A category on gpib_board
 */
@interface agilent_82357_ab : gpib_board {
@private
    //pthread_mutex_t agilent_82357a_hotplug_lock;
    CFRunLoopSourceRef m_compl_event_source;
    private_data m_private;
    unsigned short m_eos_char;
    unsigned short m_eos_mode;
    unsigned short m_hw_control_bits;
    pthread_mutex_t m_bulk_transfer_lock;
    pthread_mutex_t m_bulk_alloc_lock;
    pthread_mutex_t m_interrupt_alloc_lock;
    pthread_mutex_t m_control_alloc_lock;
    BOOL m_is_cic : YES;
}

@end
