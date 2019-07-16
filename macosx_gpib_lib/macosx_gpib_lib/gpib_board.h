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

//#import <Foundation/Foundation.h>
#import <stdatomic.h>
#import <pthread.h>
#import "gpib_user.h"


//#define HZ 1000
//#define GPIB_CODE 160
#define ERESTARTSYS 1

@class gpib_board;

/* argument for read/write/command ioctls */
/*
typedef struct
{
    UInt8 *buffer_ptr;
    UInt16 requested_transfer_count;
    UInt16 completed_transfer_count;
    BOOL end;
    SInt32 handle;
} read_write_ioctl_t;

typedef struct
{
    SInt32 handle;
    SInt32 wait_mask;
    SInt32 clear_mask;
    SInt32 set_mask;
    SInt32 ibsta;
    UInt32 pad;
    SInt32 sad;
    UInt32 usec_timeout;
} wait_ioctl_t;*/

typedef struct
{
    UInt16 pad;
    SInt16 sad;
    UInt8 parallel_poll_configuration;
    BOOL autopolling;
    BOOL is_system_controller;
    UInt32 t1_delay;
    BOOL ist : YES;
    BOOL no_7_bit_eos : YES;
} board_info_ioctl_t;

typedef struct
{
    CFRunLoopSourceRef wait;
    CFRunLoopRef runner;
    /* Used to hold the board's current status (see update_status() above)
     */
    UInt32 status;
}private_board;

struct wait_info
{
    CFRunLoopTimerRef timer;
    BOOL timed_out;
    unsigned long usec_timeout;
    private_board *board;
};

/* Used to store device-descriptor-specific information */
@interface gpib_descriptor : NSObject
{
@public
    UInt16 pad;	/* primary gpib address */
    SInt16 sad;	/* secondary gpib address (negative means disabled) */
    //atomic_t io_in_progress;
    atomic_flag io_in_progress;
    BOOL is_board : YES;
}
@end;

/* Each board has a list of gpib_status_queue to keep track of all open devices
* on the bus, so we know what address to poll when we get a service request */
@interface gpib_status_queue : NSObject
{
@public
    /* list_head so we can make a linked list of devices */
    //struct list_head list;
    UInt16 pad;	/* primary gpib address */
    SInt16 sad;	/* secondary gpib address (negative means disabled) */
    /* stores serial poll bytes for this device */
    NSMutableArray * status_bytes;
    UInt32 num_status_bytes;
    /* number of times this address is opened */
    UInt32 reference_count;
    /* flags loss of status byte error due to limit on size of queue */
    BOOL dropped_byte : YES;
}
@end;

@interface gpib_board : NSObject  {
@protected
    NSString *m_name;
    /* Watchdog timer to enable timeouts */
    CFRunLoopTimerRef m_timer;
    /* autospoll kernel thread */
    struct task_struct *m_autospoll_task;
    /* board does not support 7 bit eos comparisons */
    unsigned m_no_7_bit_eos : 1;
    /* list of open devices connected to this board */
    NSMutableArray *m_device_list;
    CFRunLoopSourceContext m_source_context;
@public
    private_board m_private_board;
    pthread_mutex_t m_big_gpib_mutex;
}

/* Flag that indicates whether board is system controller of the bus */
@property(getter=isMaster) BOOL master;
/* Flag that keeps track of whether board is up and running or not */
@property(getter=isOnline) BOOL online;
/* board's parallel poll configuration byte */
@property(getter=getPPConfig) UInt16 pPConfig;
/* primary address */
@property(getter=getPad) UInt8 pad;
/* secondary address */
@property(getter=getSad) SInt8 sad;
/* length of buffer */
@property(getter=getBufferLength) UInt16 bufferLength;
/* buffer used to store read/write data for this board */
@property(getter=getBuffer) UInt8* buffer;
/* timeout for io operations, in microseconds */
@property(getter=getUsecTimeout) UInt32 usecTimeout;
/* individual status bit */
@property(getter=getIst) BOOL ist;
/* t1 delay we are using */
@property(readwrite) UInt32 t1NanoNsec;
/* autospoll kernel thread */
@property(getter=getAutoSpoll) SInt16 autoSpoll;


-(void) getBoardInfo:(board_info_ioctl_t *) info;
+(BOOL) test_bit:(UInt32) pos : (UInt32 *) var;
+(void) set_bit:(UInt32) pos : (UInt32 *) var;
+(void) clear_bit:(UInt32) pos : (UInt32 *) var;
+(BOOL) test_and_clear_bit:(UInt32) pos : (UInt32 *) var;

/* name of board */
-(NSString *)getName;
/* attach() initializes board and allocates resources */
-(SInt32) attach;
/* detach() shuts down board and frees resources */
-(void) detach;
/* read() should read at most 'length' bytes from the bus into
 * 'buffer'.  It should return when it fills the buffer or
 * encounters an END (EOI and or EOS if appropriate).  It should set 'end'
 * to be nonzero if the read was terminated by an END, otherwise 'end'
 * should be zero.
 * Ultimately, this will be changed into or replaced by an asynchronous
 * read.  Zero return value for success, negative
 * return indicates error.
 * nbytes returns number of bytes read
 */
-(SInt32) read:(UInt8 *) buffer : (UInt32) length : (BOOL *) end : (UInt32 *) nbytes_read;
/* write() should write 'length' bytes from buffer to the bus.
 * If the boolean value send_eoi is nonzero, then EOI should
 * be sent along with the last byte.  Returns number of bytes
 * written or negative value on error.
 */
-(SInt32) write:(UInt8 *) buffer : (UInt32) length : (BOOL) send_eoi : (UInt32 *) bytes_written;
/* command() writes the command bytes in 'buffer' to the bus
 * Returns zero on success or negative value on error.
 */
-(SInt32) command:(UInt8 *)buffer : (UInt32) length : (UInt32 *) bytes_written;
/* Take control (assert ATN).  If 'asyncronous' is nonzero, take
 * control asyncronously (assert ATN immediately without waiting
 * for other processes to complete first).  Should not return
 * until board becomes controller in charge.  Returns zero no success,
 * nonzero on error.
 */
-(SInt32) take_control:(BOOL) asyncronous;
/* De-assert ATN.  Returns zero on success, nonzer on error.
 */
-(SInt32) go_to_standby;
/* request/release control of the IFC and REN lines (system controller) */
-(SInt32) request_system_control:(BOOL) request_control;
/* Asserts or de-asserts 'interface clear' (IFC) depending on
 * boolean value of 'assert'
 */
-(SInt32) interface_clear:(BOOL) assert;
/* Sends remote enable command if 'enable' is nonzero, disables remote mode
 * if 'enable' is zero
 */
-(SInt32) remote_enable:(BOOL) enable;
/* enable END for reads, when byte 'eos' is received.  If
 * 'compare_8_bits' is nonzero, then all 8 bits are compared
 * with the eos bytes.  Otherwise only the 7 least significant
 * bits are compared. */
-(SInt32) enable_eos:(uint8_t) eos : (BOOL) compare_8_bits;
/* disable END on eos byte (END on EOI only)*/
-(void) disable_eos;
/* configure parallel poll */
-(void) parallel_poll_configure:(uint8_t) configuration;
/* conduct parallel poll */
-(SInt32) parallel_poll:(uint8_t *) result;
/* set/clear ist (individual status bit) */
-(void) parallel_poll_response:(UInt32) ist;
/* Returns current status of the bus lines.  Should be set to
 * NULL if your board does not have the ability to query the
 * state of the bus lines. */
-(SInt32) line_status;
/* updates and returns the board's current status.
 * The meaning of the bits are specified in gpib_user.h
 * in the IBSTA section.  The driver does not need to
 * worry about setting the CMPL, END, TIMO, or ERR bits.
 */
-(UInt32) update_status:(UInt32) clear_mask;
/* Sets primary address 0-30 for gpib interface card.
 */
-(SInt32) primary_address:(UInt16) address;
/* Sets and enables, or disables secondary address 0-30
 * for gpib interface card.
 */
-(void) secondary_address:(UInt16) address : (BOOL) enable;
/* Sets the byte the board should send in response to a serial poll.
 * Function should also request service if appropriate.
 */
-(void) serial_poll_response:(UInt8) status;
/* returns the byte the board will send in response to a serial poll.
 */
-(UInt8) serial_poll_status;
/* adjust T1 delay */
-(UInt32) t1_delay:(UInt32) nano_sec;
/* go to local mode */
-(void) return_to_local;

-(id) init_gpib_board;
-(SInt32) subtract_open_device_count:(UInt32) pad : (SInt32) sad : (UInt32) count;
-(SInt32) decrement_open_device_count:(UInt32) pad : (SInt32) sad;
-(SInt32) increment_open_device_count:(UInt32) pad : (SInt32) sad;
-(void) init_gpib_status_queue:(gpib_status_queue *) device;
-(void) osStartTimer;
-(void) osStartTimer:(UInt32) usec_timeout;
-(void) osRemoveTimer;
-(void) startWaitTimer:(struct wait_info *) winfo;
-(void) removeWaitTimer:(struct wait_info *) winfo;
-(void) init_wait_info: (struct wait_info *) winfo;
-(BOOL) io_timed_out;
-(SInt32) gpib_allocate_board:(UInt32) length;
-(void) gpib_deallocate_board;
-(UInt32) num_status_bytes:(gpib_status_queue *) dev;
-(SInt32) push_status_byte:(gpib_status_queue *) device : (UInt8) poll_byte;
-(SInt32) pop_status_byte:(gpib_status_queue *) device : (UInt8 *) poll_byte;
-(gpib_status_queue *) get_gpib_status_queue:(UInt32) pad : (SInt32) sad;

@end
