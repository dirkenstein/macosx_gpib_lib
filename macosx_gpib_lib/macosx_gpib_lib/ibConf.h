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

/* meaning for flags */

#define CN_SDCL    (1<<1)             /* Send DCL on init                */
#define CN_SLLO    (1<<2)             /* Send LLO on init                */
#define CN_NETWORK (1<<3)             /* is a network device             */
#define CN_AUTOPOLL (1<<4)            /* Auto serial poll devices        */
#define CN_EXCLUSIVE (1<<5)           /* Exclusive use only */

/*---------------------------------------------------------------------- */

@interface async_operation : NSObject{
@public
	//pthread_t thread;	/* thread used for asynchronous io operations */
    NSThread *thread;
	pthread_mutex_t lock;
	pthread_mutex_t join_lock;
	//pthread_cond_t condition;
    NSCondition* condition;
	UInt8 *buffer;
	volatile long buffer_length;
	volatile int iberr;
	volatile int ibsta;
	volatile long ibcntl;
	volatile BOOL in_progress;
	volatile short abort;
}
@end;

typedef struct
{
	int pad;	/* device primary address */
	int sad;	/* device secodnary address (negative disables) */
	int board;	/* board index */
	unsigned int usec_timeout;
	unsigned int spoll_usec_timeout;
	unsigned int ppoll_usec_timeout;
	char eos;                           /* eos character */
	int eos_flags;
	int ppoll_config;	/* current parallel poll configuration */
	BOOL send_eoi : YES;	/* assert EOI at end of writes */
	BOOL local_lockout : YES;	/* send local lockout when device is brought online */
	BOOL local_ppc : YES;	/* enable local configuration of board's parallel poll response */
	BOOL readdr : YES;	/* useless, exists for compatibility only at present */
}descriptor_settings_t;

@interface ibConf_t : NSObject{
@public
	int handle;
	char name[100];		/* name of the device (for ibfind())     */
	descriptor_settings_t defaults;	/* initial settings stored so ibonl() can restore them */
	descriptor_settings_t settings;	/* various software settings for this descriptor */
	char init_string[100];               /* initialization string (optional) */
	int flags;                         /* some flags, deprecated          */
	async_operation *async;	/* used by asynchronous operations ibcmda(), ibrda(), etc. */
	BOOL end : YES;	/* EOI asserted or EOS received at end of IO operation */
	BOOL is_interface : YES;	/* is interface board */
	BOOL board_is_open : YES;
	BOOL has_lock : YES;
	BOOL timed_out : YES;		/* io operation timed out */
}
@end;

















