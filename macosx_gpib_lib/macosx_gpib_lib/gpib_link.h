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

#import "gpib_sys.h"


/* Standard functions. */
enum gpib_ioctl
{
    IBRD,
    IBWRT,
    IBCMD,
    IBOPENDEV,
    IBCLOSEDEV,
    IBWAIT,
    IBRPP,
    IBSIC,
    IBSRE,
    IBGTS,
    IBCAC,
    IBLINES,
    IBPAD,
    IBSAD,
    IBTMO,
    IBRSP,
    IBEOS,
    IBRSV,
    IBMUTEX,
    IBSPOLL_BYTES,
    IBPPC,
    IBBOARD_INFO,
    IBQUERY_BOARD_RSV,
    IBRSC,
    IB_T1_DELAY,
    IBLOC,
    IBAUTOSPOLL,
    IBONL
};

@interface gpib_link : gpib_sys
{
@protected
    BOOL m_autospoll;
    NSThread *m_linkthread;
    NSPort *m_port;
    Class m_class_gpib_board;
}

-(int) ibopen;
-(int) ibclose;
-(int) close;
-(NSString*) ibname;
-(BOOL) isAutoSpoll;
-(void) setAutoSpoll:(BOOL) enable;
-(id) init_gpib_link:(Class) class_gpib_board;
-(int) ioctl:(gpib_link_arg *)arg;

@end
