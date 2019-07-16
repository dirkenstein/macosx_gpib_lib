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

@interface gpib_link_arg : NSObject
{
@public
    unsigned int cmd;
    unsigned int nNumBytes;
    short nLines;
    int retval;
    int handle;
    int pad;
    int sad;
    unsigned int nDelay;
    int nEos;
    int nEosFlags;
    int nStatus;
    BOOL bOnline;
    BOOL bAutospoll;
    BOOL bMutex;
    BOOL bIsBoard;
    BOOL bTakeControl;
    board_info_ioctl_t boardInfo;
    //read_write_ioctl_t readWrite;
    NSMutableDictionary * read_ioctl;
    //wait_ioctl_t wait;
    unsigned int nConfig;
    BOOL bSetIst;
    BOOL bClearIst;
    uint8_t nPollByte;
    BOOL bRequestControl;
    UInt8 nStatusByte;
    UInt32 nUsecDuration;
    BOOL bEnable;
    NSString* name;
}@end;

@interface gpib_sys : NSObject  {
@protected
    gpib_board* m_board;
    atomic_flag m_holding_mutex;
    //gpib_descriptor_t *m_descriptors[ GPIB_MAX_NUM_DESCRIPTORS ];
    NSMutableArray* m_descriptors;
    /* locked while descriptors are being allocated/deallocated */
    pthread_mutex_t  m_descriptors_mutex;
    /* Lock that only allows one process to access this board at a time.
     Has to be first in any locking order, since it can be locked over
     multiple ioctls. */
    pthread_mutex_t m_user_mutex;
    BOOL m_use_event_queue;
}
//-(void) init_board_array:(unsigned int) length;
-(int) serial_poll_all:(unsigned int) usec_timeout;
-(void) init_gpib_descriptor:(gpib_descriptor *) desc;
-(int) dvrsp:(unsigned int) pad : (int) sad : (unsigned int) usec_timeout : (uint8_t *) result;
-(int) ibcac:(int) sync;
-(SInt32) ibcmd : (UInt8 *) buf : (UInt32) length : (UInt32 *) bytes_written;
-(int) ibgts;
-(int) ibonline;
-(int) iboffline;
-(int) iblines:(short *) lines;
-(int) ibrd : (UInt8 *) buf : (UInt32) length : (BOOL *) end_flag : (UInt32 *) nbytes_read;
-(int) ibrpp:(uint8_t *) result;
-(int) ibrsv:(unsigned int)  poll_status;
-(void) ibrsc:(BOOL) request_control;
-(int) ibsic:(unsigned int) usec_duration;
-(int) ibsre:(BOOL) enable;
-(int) ibpad: (unsigned int) addr;
-(int) ibsad:(int) addr;
-(int) ibeos:(int) eos : (int) eosflags;
-(int) ibwait:(int) wait_mask : (int) clear_mask : (int) set_mask : (int *) status : (unsigned long) usec_timeout : (gpib_descriptor *) desc;
-(SInt32) ibwrt : (UInt8 *) buf : (UInt32) cnt : (BOOL) send_eoi : (UInt32 *) bytes_written;
-(int) ibstatus;
-(int) general_ibstatus:(gpib_status_queue *) device : (int) clear_mask : (int) set_mask : (gpib_descriptor *) desc;
-(int) ibppc:(unsigned int) configuration;
-(int) wait_satisfied:(struct wait_info *) winfo : (gpib_status_queue *) status_queue : (int) wait_mask : (int *) status : (gpib_descriptor *) desc;
// autospoll.h
-(int) get_serial_poll_byte:(unsigned int) pad : (int) sad : (unsigned int) usec_timeout : (uint8_t*) poll_byte;
-(int) autopoll_all_devices;


// device.h
-(int) setup_serial_poll:(unsigned int) usec_timeout;
-(int) read_serial_poll_byte:(unsigned int) pad : (int) sad :(unsigned int) usec_timeout : (uint8_t*) result;
-(int) cleanup_serial_poll:(unsigned int) usec_timeout;
-(int) serial_poll_single:(unsigned int) pad : (int) sad :(unsigned int) usec_timeout : (uint8_t *) result;
-(gpib_descriptor*) handle_to_descriptor:(int) handle;
-(int) cleanup_open_devices;
//-(void) init_gpib_sys:(gpib_board*) board;
-(void) init_gpib_sys:(Class) classBoard;
-(BOOL) use_event_queue;
-(void) getBoardName:(gpib_link_arg*) arg;
@end
