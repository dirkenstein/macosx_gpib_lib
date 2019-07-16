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

@class gpib_visa_internal;

@interface gpib_visa : NSObject{
@private
    gpib_visa_internal *m_gpib_visa_internal;
}

-(void) AllSpoll:(int) boardID : (uint16_t *) addressList : (short *) resultList;
-(void) DevClear:(int) boardID : (uint16_t) address;
-(void) DevClearList:(int) boardID : (uint16_t *) addressList;
-(void) EnableLocal:(int) boardID : (uint16_t *) addressList;
-(void) EnableRemote:(int) boardID : (uint16_t *) addressList;
-(void) FindLstn:(int) boardID : (uint16_t *) padList : (uint16_t *) resultList : (int) maxNumResults;
-(void) FindRQS:(int) boardID : (uint16_t *) addressList : (short *) result;
-(void) PassControl:(int) boardID : (uint16_t) address;
-(void) PPoll:(int) boardID : (short *) result;
-(void) PPollConfig:(int) boardID : (uint16_t) address : (int) dataLine : (int) lineSense;
-(void) PPollUnconfig:(int) boardID : (uint16_t *) addressList;
-(void) RcvRespMsg:(int) boardID : (void *) buffer : (long) count : (int) termination;
-(void) ReadStatusByte:(int) boardID : (uint16_t) address : (short *) result;
-(void) Receive:(int) boardID : (uint16_t) address : (void *) buffer : (long) count : (int) termination;
-(void) ReceiveSetup:(int) boardID : (uint16_t) address;
-(void) ResetSys:(int) boardID : (uint16_t *) addressList;
-(void) Send:(int) boardID : (uint16_t) address : (void *) buffer : (long) count : (int) eot_mode;
-(void) SendCmds:(int) boardID : (void *) cmds : (long) count;
-(void) SendDataBytes:(int) boardID : (void *) buffer : (long) count : (int) eotmode;
-(void) SendIFC:(int) boardID;
-(void) SendLLO:(int) boardID;
-(void) SendList:(int) boardID : (uint16_t *) addressList : (void *) buffer : (long) count : (int) eotmode;
-(void) SendSetup:(int) boardID : (uint16_t *) addressList;
-(void) SetRWLS:(int) boardID : (uint16_t *) addressList;
-(void) TestSRQ:(int) boardID : (short *) result;
-(void) TestSys:(int) boardID : (uint16_t *) addressList : (short *) resultList;
-(void) Trigger:(int) boardID : (uint16_t *) address;
-(void) TriggerList:(int) boardID : (uint16_t *) addressList;
-(void) WaitSRQ:(int) boardID : (short *) result;
-(const char*) ibname:(int) boardID;
-(int) ibask:(int) boardID : (int) option : (int *) value;
-(int) ibbna:(int) boardID : (char *) board_name;
-(int) ibcac:(int) boardID : (BOOL) synchronous;
-(int) ibclr:(int) boardID;
-(int) ibcmd:(int) boardID : (void *) cmd : (long) cnt;
-(int) ibcmda:(int) boardID : (void *) cmd : (long) cnt;
-(int) ibconfig:(int) boardID : (int) option : (int) value;
-(int) ibdev:(int) board_index : (int) pad : (int) sad : (int) timo : (BOOL) send_eoi : (int) eosmode;
-(int) ibeot:(int) boardID : (BOOL) send_eoi;
-(int) ibeos:(int) boardID : (int) v;
-(int) ibfind:(const char *) name;
-(int) ibcount;
-(int) ibgts:(int) boardID : (int) shadow_handshake;
-(int) ibist:(int) boardID : (int) ist;
-(int) iblines:(int) boardID : (short *) line_status;
-(int) ibln:(int) boardID : (int) pad : (int) sad : (short *) found_listener;
-(int) ibloc:(int) boardID;
-(int) ibonl:(int) boardID : (BOOL) onl;
-(int) ibpad:(int) boardID : (int) address;
-(int) ibpct:(int) boardID;
-(int) ibppc:(int) boardID : (int) v;
//-(int) ibrd:(int) boardID : (void *) buf : (long) count;
-(int) ibrd:(int) boardID : (void *) buf : (long) count;
-(int) ibrda:(int) boardID : (void *) buf : (long) count;
-(int) ibrdf:(int) boardID : (char *) file_path;
-(int) ibrpp:(int) boardID : (char *) ppr;
-(int) ibrsc:(int) boardID : (BOOL) request_control;
-(int) ibrsp:(int) boardID : (UInt8 *) spr;
-(int) ibrsv:(int) boardID : (int) v;
-(int) ibsad:(int) boardID : (int) address;
-(int) ibsic:(int) boardID;
-(int) ibsre:(int) boardID : (BOOL) enable;
-(int) ibstop:(int) boardID;
-(int) ibtmo:(int) boardID : (int) timeout;
-(int) ibtrg:(int) boardID;
-(int) ibspb:(int) boardID : (short *) sp_bytes;
-(const char*) ibvers;
-(int) ibwait:(int) boardID : (int) mask;
-(int) ibwrt:(int) boardID : (void *) buffer : (long) count;
-(int) ibwrta:(int) boardID : (void *) buffer : (long) count;
-(int) ibwrtf:(int) boardID : (char *) file_path;
-(int) ibclose:(int) boardID;
-(int) ibopen:(int) boardID;
-(void) close;
-(const char*) gpib_error_string:(int) error;
-(void) setIbsta:(int) status;
-(void) setIberr:(int) error;
-(void) setIbcnt:(long) count;
-(int) ThreadIbsta;
-(int) ThreadIberr;
-(int) ThreadIbcnt;

@end
