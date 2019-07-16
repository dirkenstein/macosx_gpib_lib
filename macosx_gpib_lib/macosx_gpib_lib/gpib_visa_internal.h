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

#import "gpib_link.h"
#import "ibConf.h"

#define GPIB_CONFIGS_LENGTH 0x1000
#define FIND_CONFIGS_LENGTH 64	/* max number of devices we can read from config file */

static const uint16_t NOADDR = (uint16_t)-1;


/* tells RcvRespMsg() to stop on EOI */
static const int STOPend = 0x100;
static const int default_ppoll_usec_timeout = 2;
static const int sad_offset = 0x60;

@interface gpib_aio_arg : NSObject
{
@public
    int ud;
    ibConf_t *conf;
    int gpib_aio_type;
    size_t count;
}
@end;

enum sad_special_address
{
    NO_SAD = 0,
    ALL_SAD = -1
};

enum send_eotmode
{
    NULLend = 0,
    DABend = 1,
    NLend = 2
};

/* support for async io (ibrda() ibwrta(), etc.) */
enum gpib_aio_varieties
{
    GPIB_AIO_COMMAND,
    GPIB_AIO_READ,
    GPIB_AIO_WRITE,
};

enum internal_gpib_addr
{
    SAD_DISABLED = -1,
    ADDR_INVALID = -2
};

static const char* error_descriptions[] =
{
    "EDVR 0: OS error",
    "ECIC 1: Board not controller in charge",
    "ENOL 2: No listeners",
    "EADR 3: Improper addressing",
    "EARG 4: Bad argument",
    "ESAC 5: Board not system controller",
    "EABO 6: Operation aborted",
    "ENEB 7: Non-existant board",
    "EDMA 8: DMA error",
    "libmacosx_gpib: Unknown error code 9",
    "EOIP 10: IO operation in progress",
    "ECAP 11: Capability does not exist",
    "EFSO 12: File system error",
    "libmacosx_gpib: Unknown error code 13",
    "EBUS 14: Bus error",
    "ESTB 15: Lost status byte",
    "ESRQ 16: Stuck service request",
    "libmacosx_gpib: Unknown error code 17",
    "libmacosx_gpib: Unknown error code 18",
    "libmacosx_gpib: Unknown error code 19",
    "ETAB 20: Table problem",
};

@interface gpib_visa_internal : NSObject{
@protected
    int ibsta;
    int ibcnt;
    int iberr;
    long ibcntl;
    ibConf_t *ibConfigs[ GPIB_CONFIGS_LENGTH ];
    ibConf_t *ibFindConfigs[ FIND_CONFIGS_LENGTH ];
    //gpib_link * m_ibBoard[ GPIB_MAX_NUM_BOARDS ];
    NSMutableArray *board_list;
    NSMutableDictionary *thread_key;
    NSMutableArray *ibConfigs_list;
}

+(uint16_t) MakeAddr:(UInt8) pad : (UInt8) sad;
+(UInt8) GetPAD:(uint16_t) address;
+(UInt8) GetSAD:(uint16_t) address;

-(void) globals_alloc;
-(int) findBoardWithName:(const char *) name;
-(void) init_descriptor_settings:(descriptor_settings_t *) settings;
-(int) insert_descriptor:(ibConf_t*) conf : (int) ud;
-(int) my_wait:(ibConf_t *)conf : (int) wait_mask : (int) clear_mask : (int) set_mask : (int *) status;
-(void) init_async_op:(async_operation *) async;
-(int) ibBoardOpen:(int) boardId;
-(int) ibBoardClose:(int) boardId;
-(int) iblcleos:(ibConf_t *) conf;
-(const char*) ibBoardName:(int) boardId;
-(void) close;
-(int) ibGetDescriptor:(ibConf_t*) conf;
-(int) ibFindDevIndex:(char *) name;
-(ssize_t) my_ibcmd:(ibConf_t *) conf : (UInt8 *) buffer : (size_t) length;
-(ssize_t) my_ibrd:(ibConf_t *) conf : (UInt8 *) buffer : (size_t) count : (size_t *) bytes_read;
-(int) my_ibwrt:(ibConf_t *) conf : (UInt8 *) buffer : (size_t) count : (size_t *) bytes_written;
-(UInt8) send_setup_string:(ibConf_t *) conf : (UInt8 *) cmdString;
-(UInt8) create_send_setup:(gpib_link *) board : (uint16_t *) addressList : (UInt8 *) cmdString;
-(int) send_setup:(ibConf_t *) conf;
-(void) init_ibconf:(ibConf_t *) conf;
-(int) my_ibbna:(ibConf_t *) conf : (UInt8) new_board_index;
-(int) my_trigger:(ibConf_t *)conf : (uint16_t*) addressList;
-(unsigned int) timeout_to_usec:(enum gpib_timeout) timeout;
-(unsigned int) ppoll_timeout_to_usec:(UInt32) timeout;
-(unsigned int) usec_to_ppoll_timeout:(UInt32) usec;
-(int) set_timeout:(gpib_link *) board : (UInt32) usec_timeout;
-(int) close_gpib_handle:(ibConf_t *) conf;
-(int) open_gpib_handle:(ibConf_t *) conf;
-(int) gpibi_change_address:(ibConf_t *) conf : (UInt8) pad : (int) sad;
-(int) lock_board_mutex:(gpib_link *) board;
-(int) unlock_board_mutex:(gpib_link *) board;
-(int) conf_lock_board:(ibConf_t *) conf;
-(void) conf_unlock_board:(ibConf_t *) conf;
-(int) ibstatus:(ibConf_t *) conf : (BOOL) error : (int) clear_mask : (int) set_mask;
-(int) exit_library:(int) ud : (BOOL) error;
-(int) general_exit_library:(int) ud : (BOOL) error : (BOOL) no_sync_globals : (BOOL) no_update_ibsta : (int) status_clear_mask : (int) status_set_mask : (BOOL) no_unlock_board;
-(unsigned int) usec_to_timeout:(unsigned int) usec;
-(int) query_ppc:(gpib_link *) board;
-(int) query_ist:(gpib_link *) board;
-(int) query_autopoll:(gpib_link *) board;
-(int) query_pad:(gpib_link *) board : (UInt8 *) pad;
-(int) query_sad:(gpib_link *) board : (int *) sad;
-(int) query_board_t1_delay:(gpib_link *) board;
-(int) query_board_rsv:(gpib_link *) board;
-(int) query_no_7_bit_eos:(gpib_link *) board;
-(int) conf_online:(ibConf_t *) conf : (BOOL) online;
-(int) configure_autospoll:(ibConf_t *) conf : (BOOL) enable;
-(int) extractPAD:(uint16_t) address;
-(int) extractSAD:(uint16_t) address;
-(uint16_t) packAddress:(UInt8) pad : (int) sad;
-(BOOL) addressIsValid:(uint16_t) address;
-(BOOL) addressListIsValid:(uint16_t *) addressList;
-(UInt8) numAddresses:(uint16_t *) addressList;
-(int) remote_enable:(gpib_link *) board : (BOOL) enable;
-(int) config_read_eos:(gpib_link *) board : (BOOL) use_eos_char : (int) eos_char : (BOOL) compare_8_bits;
-(void) sync_globals;
-(int) is_system_controller:(gpib_link *) board;
-(BOOL) is_cic:(gpib_link *) board;
-(int) assert_ifc:(gpib_link *) board : (UInt8) usec;
-(int) request_system_control:(gpib_link *) board : (BOOL) request_control;
-(int) internal_ibpad:(ibConf_t *) conf : (UInt8) address;
-(int) internal_ibsad:(ibConf_t *) conf : (int) address;
-(int) internal_ibtmo:(ibConf_t *) conf : (int) timeout;
-(void) internal_ibeot:(ibConf_t *) conf : (BOOL) send_eoi;
-(int) internal_ibist:(ibConf_t *) conf : (BOOL) ist;
-(int) internal_ibppc:(ibConf_t *) conf : (int) v;
-(int) internal_ibsre:(ibConf_t *) conf : (BOOL) enable;
-(int) internal_ibrsv:(ibConf_t *) conf : (UInt8) status_byte;
-(int) internal_iblines:(ibConf_t *) conf : (short *) line_status;
-(int) internal_ibgts:(ibConf_t *) conf : (int) shadow_handshake;
-(int) internal_ibrsc:(ibConf_t *) conf : (int) request_control;
-(int) internal_ibsic:(ibConf_t *) conf;
-(int) internal_ibstop:(ibConf_t *) conf;
-(int) internal_ibrpp:(ibConf_t *) conf : (char *) result;
-(int) InternalDevClearList:(ibConf_t *) conf : (uint16_t *) addressList;
-(int) InternalReceiveSetup:(ibConf_t *) conf : (uint16_t) address;
-(int) InternalSendSetup:(ibConf_t *) conf : (uint16_t *) addressList;
-(int) InternalSendList:(ibConf_t *) conf : (uint16_t *) addressList : (void *) buffer : (long) count : (int) eotmode;
-(int) InternalSendDataBytes:(ibConf_t *) conf : (void *) buffer : (size_t) count : (int) eotmode;
-(int) InternalEnableRemote:(ibConf_t *) conf : (uint16_t *) addressList;
-(int) InternalReceive:(ibConf_t *) conf : (uint16_t) address : (void *) buffer : (long) count : (int) termination;
-(int) InternalRcvRespMsg:(ibConf_t *) conf : (void *) buffer : (long) count : (int) termination;
-(int) InternalResetSys:(ibConf_t *) conf : (uint16_t *) addressList;
-(int) InternalTestSys:(ibConf_t *) conf : (uint16_t *) addressList : (short *) resultList;
-(gpib_link *) interfaceBoard:(ibConf_t *) conf;
-(int) ibCheckDescriptor:(int) ud;
-(int) board_online:(int) boardId : (BOOL) online;
-(int) gpib_aio_launch:(int) ud : (ibConf_t *) conf : (int) gpib_aio_type : (void *) buffer : (long) cnt;
-(int) set_spoll_timeout:(ibConf_t *) conf : (int) timeout;
-(int) set_ppoll_timeout:(ibConf_t *)conf : (int) timeout;
-(int) set_t1_delay:(gpib_link *)board : (int) delay;
-(int) listenerFound:(ibConf_t *) conf :(uint16_t *) addressList;
-(int) secondaryListenerFound:(ibConf_t *) conf : (UInt8) pad;
-(int) reinit_descriptor:(ibConf_t *) conf;
-(int) my_pass_control:(ibConf_t *) conf : (UInt8) pad : (int) sad;
-(int) device_ppc:(ibConf_t *) conf : (int) ppc_configuration;
-(int) board_ppc:(ibConf_t *) conf : (int) ppc_configuration;
-(int) ppoll_configure_device:(ibConf_t *) conf : (uint16_t *) addressList : (int) ppc_configuration;
-(ssize_t) read_data:(ibConf_t *) conf : (UInt8 *) buffer : (size_t) count : (size_t *) bytes_read;
-(int) serial_poll:(gpib_link *) board : (UInt8) pad : (SInt8) sad : (UInt32) usec_timeout : (UInt8 *) result;
-(void) fixup_status_bits:(ibConf_t *)conf : (int *) status;
-(int) send_data:(ibConf_t *)conf : (void *) buffer : (size_t) count : (BOOL) send_eoi : (size_t *) bytes_written;
-(int) my_ibwrtf:(ibConf_t *) conf : (char *) file_path : (size_t *) bytes_written;
-(int) send_data_smart_eoi:(ibConf_t *) conf : (void *) buffer : (size_t) count : (int) force_eoi : (size_t *) bytes_written;
-(int) find_eos:(UInt8 *) buffer : (size_t) length : (int) eos : (int) eos_flags;
-(int) local_lockout:(ibConf_t *) conf : (uint16_t *) addressList;
-(void) do_aio:(gpib_aio_arg *)arg;
-(int) my_ibdev:(ibConf_t*) new_conf;
-(ibConf_t *) enter_library:(int) ud;
-(ibConf_t *) general_enter_library:(int) ud : (BOOL) no_lock_board : (BOOL) ignore_eoip;
-(int) boardCount;
-(void) setIbsta:(int) status;
-(void) setIberr:(int) error;
-(void) setIbcnt:(long) count;
-(int) ThreadIbsta;
-(int) ThreadIberr;
-(int) ThreadIbcnt;

@end
