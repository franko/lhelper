/********************************************************************************
*                                                                               *
*                    M u l t i - L i ne   T e x t   O b j e c t                 *
*                                                                               *
*********************************************************************************
* Copyright (C) 1998,2016 by Jeroen van der Zijp.   All Rights Reserved.        *
*********************************************************************************
* This library is free software; you can redistribute it and/or modify          *
* it under the terms of the GNU Lesser General Public License as published by   *
* the Free Software Foundation; either version 3 of the License, or             *
* (at your option) any later version.                                           *
*                                                                               *
* This library is distributed in the hope that it will be useful,               *
* but WITHOUT ANY WARRANTY; without even the implied warranty of                *
* MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the                 *
* GNU Lesser General Public License for more details.                           *
*                                                                               *
* You should have received a copy of the GNU Lesser General Public License      *
* along with this program.  If not, see <http://www.gnu.org/licenses/>          *
********************************************************************************/
#include "xincs.h"
#include "fxver.h"
#include "fxdefs.h"
#include "fxmath.h"
#include "fxkeys.h"
#include "fxascii.h"
#include "fxunicode.h"
#include "FXArray.h"
#include "FXHash.h"
#include "FXMutex.h"
#include "FXStream.h"
#include "FXString.h"
#include "FXElement.h"
#include "FXException.h"
#include "FXRex.h"
#include "FXSize.h"
#include "FXPoint.h"
#include "FXRectangle.h"
#include "FXObject.h"
#include "FXStringDictionary.h"
#include "FXSettings.h"
#include "FXRegistry.h"
#include "FXAccelTable.h"
#include "FXFont.h"
#include "FXEvent.h"
#include "FXWindow.h"
#include "FXDCWindow.h"
#include "FXApp.h"
#include "FXGIFIcon.h"
#include "FXScrollBar.h"
#include "FXText.h"
#include "FXComposeContext.h"
#include "icons.h"



/*
  Notes:
  - Line start array is one longer than number of visible lines.
  - Control characters in the buffer are OK (e.g. ^L)
  - Drag cursor should be same as normal one until drag starts!
  - Change of cursor only implies makePositionVisible() if done by user.
  - Buffer layout:

    Content  :  A  B  C  .  .  .  .  .  .  .  .  D  E  F  G
    Position :  0  1  2 			                   3  4  5  6    length=7
    Addresss :  0  1  2  3  4  5  6  7  8  9 10 11 12 13 14    buffersize=7+11-3=15
                         ^		               	 ^
	           	       	 |			                |
	     	                gapstart=3	           gapend=11      gaplen=11-3=8

    The gap is moved around the buffer so newly added text can be entered into the gap;
    when the gap becomes too small, the buffer is resized.
    This gapped-buffer technique minimizes the number of resizes of the buffer, and
    minimizes the number of block moves.

    The tail end of the visrows array will look like:

    visrow[0]= 0: "Q R S T U V W \n"
    visrow[1]= 8: "X Y Z"
    visrow[2]=11: <no text>
    visrow[3]=11: <no text>            length = 11

    The last legal position is length = 11.

  - While resizing window, keep track of a position which should remain visible, i.e.
    toppos=rowStart(position).  The position is changed same as toppos, except during
    resize.
  - When changing text, if we're looking at the tail end of the buffer, avoid jumping
    the top lines when the content hight shrinks.
  - Add undo capability. (First undo will turn mod flag back off).
  - Add incremental search, search/replace, selection search.
  - Style table stuff.
  - Need to allow for one single routine to update style buffer same as text buffer
  - Maybe put all keyboard bindings into accelerator table.
  - Variable cursorcol should take tabcolumns into account.
  - Italic fonts are bit problematic on border between selected/unselected text
    due to kerning.
  - Tab should work as tabcolumns columns when computing a column.
  - Need rectangular selection capability.
  - Perhaps split off buffer management into separate text buffer class (allows for
    multiple views).
  - Improve book keeping based on line/column numbers, not rows/characters.
  - If there is a style table, the style buffer is used as index into the style table,
    allowing for up to 255 styles (style index==0 is the default style).
    The style member in the FXHiliteStyle struct is used for underlining, strikeouts,
    and other effects.
    If there is NO style table but there is a style buffer, the style buffer can still
    be used for underlining, strikeouts, and other effects.
  - Sending SEL_CHANGED is pretty useless; should only be sent AFTER text change,
    and void* should contain some sensible info.
  - When in overstrike mode and having a selection, entering a character should
    replace the selection, not delete the selection and then overstrike the character
    after the selection.
  - When pasting or dropping whole lines, insert at begin of line instead of at cursor;
    question:- how to know we're pasting whole lines?
  - Need block cursor when in overstrike mode.
  - Inserting lots of stuff should show cursor.
  - Perhaps change text and style buffer to FXString for further complexity reduction.
  - FIXME use getVisibleX() and getVisibleY() everywhere!
*/


#define MINSIZE         80              // Minimum gap size
#define NVISROWS        20              // Initial visible rows
#define MAXTABCOLUMNS   32              // Maximum tab column setting

#define TEXT_MASK       (TEXT_FIXEDWRAP|TEXT_WORDWRAP|TEXT_OVERSTRIKE|TEXT_READONLY|TEXT_NO_TABS|TEXT_AUTOINDENT|TEXT_SHOWACTIVE)

using namespace FX;

/*******************************************************************************/

namespace FX {


// Furnish our own version
extern FXAPI FXint __snprintf(FXchar* string,FXint length,const FXchar* format,...);


// Map
FXDEFMAP(FXText) FXTextMap[]={
  FXMAPFUNC(SEL_PAINT,0,FXText::onPaint),
  FXMAPFUNC(SEL_MOTION,0,FXText::onMotion),
  FXMAPFUNC(SEL_DRAGGED,0,FXText::onDragged),
  FXMAPFUNC(SEL_TIMEOUT,FXText::ID_BLINK,FXText::onBlink),
  FXMAPFUNC(SEL_TIMEOUT,FXText::ID_FLASH,FXText::onFlash),
  FXMAPFUNC(SEL_TIMEOUT,FXText::ID_AUTOSCROLL,FXText::onAutoScroll),
  FXMAPFUNC(SEL_FOCUSIN,0,FXText::onFocusIn),
  FXMAPFUNC(SEL_FOCUSOUT,0,FXText::onFocusOut),
  FXMAPFUNC(SEL_BEGINDRAG,0,FXText::onBeginDrag),
  FXMAPFUNC(SEL_ENDDRAG,0,FXText::onEndDrag),
  FXMAPFUNC(SEL_LEFTBUTTONPRESS,0,FXText::onLeftBtnPress),
  FXMAPFUNC(SEL_LEFTBUTTONRELEASE,0,FXText::onLeftBtnRelease),
  FXMAPFUNC(SEL_MIDDLEBUTTONPRESS,0,FXText::onMiddleBtnPress),
  FXMAPFUNC(SEL_MIDDLEBUTTONRELEASE,0,FXText::onMiddleBtnRelease),
  FXMAPFUNC(SEL_RIGHTBUTTONPRESS,0,FXText::onRightBtnPress),
  FXMAPFUNC(SEL_RIGHTBUTTONRELEASE,0,FXText::onRightBtnRelease),
  FXMAPFUNC(SEL_UNGRABBED,0,FXText::onUngrabbed),
  FXMAPFUNC(SEL_DND_ENTER,0,FXText::onDNDEnter),
  FXMAPFUNC(SEL_DND_LEAVE,0,FXText::onDNDLeave),
  FXMAPFUNC(SEL_DND_DROP,0,FXText::onDNDDrop),
  FXMAPFUNC(SEL_DND_MOTION,0,FXText::onDNDMotion),
  FXMAPFUNC(SEL_DND_REQUEST,0,FXText::onDNDRequest),
  FXMAPFUNC(SEL_SELECTION_LOST,0,FXText::onSelectionLost),
  FXMAPFUNC(SEL_SELECTION_GAINED,0,FXText::onSelectionGained),
  FXMAPFUNC(SEL_SELECTION_REQUEST,0,FXText::onSelectionRequest),
  FXMAPFUNC(SEL_CLIPBOARD_LOST,0,FXText::onClipboardLost),
  FXMAPFUNC(SEL_CLIPBOARD_GAINED,0,FXText::onClipboardGained),
  FXMAPFUNC(SEL_CLIPBOARD_REQUEST,0,FXText::onClipboardRequest),
  FXMAPFUNC(SEL_KEYPRESS,0,FXText::onKeyPress),
  FXMAPFUNC(SEL_KEYRELEASE,0,FXText::onKeyRelease),
  FXMAPFUNC(SEL_QUERY_TIP,0,FXText::onQueryTip),
  FXMAPFUNC(SEL_QUERY_HELP,0,FXText::onQueryHelp),
  FXMAPFUNC(SEL_IME_START,0,FXText::onIMEStart),
  FXMAPFUNC(SEL_UPDATE,FXText::ID_TOGGLE_EDITABLE,FXText::onUpdToggleEditable),
  FXMAPFUNC(SEL_UPDATE,FXText::ID_TOGGLE_OVERSTRIKE,FXText::onUpdToggleOverstrike),
  FXMAPFUNC(SEL_UPDATE,FXText::ID_CURSOR_ROW,FXText::onUpdCursorRow),
  FXMAPFUNC(SEL_UPDATE,FXText::ID_CURSOR_COLUMN,FXText::onUpdCursorColumn),
  FXMAPFUNC(SEL_UPDATE,FXText::ID_CUT_SEL,FXText::onUpdHaveEditableSelection),
  FXMAPFUNC(SEL_UPDATE,FXText::ID_COPY_SEL,FXText::onUpdHaveSelection),
  FXMAPFUNC(SEL_UPDATE,FXText::ID_PASTE_SEL,FXText::onUpdIsEditable),
  FXMAPFUNC(SEL_UPDATE,FXText::ID_DELETE_SEL,FXText::onUpdHaveEditableSelection),
  FXMAPFUNC(SEL_UPDATE,FXText::ID_REPLACE_SEL,FXText::onUpdHaveEditableSelection),
  FXMAPFUNC(SEL_UPDATE,FXText::ID_UPPER_CASE,FXText::onUpdHaveEditableSelection),
  FXMAPFUNC(SEL_UPDATE,FXText::ID_LOWER_CASE,FXText::onUpdHaveEditableSelection),
  FXMAPFUNC(SEL_UPDATE,FXText::ID_CLEAN_INDENT,FXText::onUpdHaveEditableSelection),
  FXMAPFUNC(SEL_COMMAND,FXText::ID_CURSOR_TOP,FXText::onCmdCursorTop),
  FXMAPFUNC(SEL_COMMAND,FXText::ID_CURSOR_BOTTOM,FXText::onCmdCursorBottom),
  FXMAPFUNC(SEL_COMMAND,FXText::ID_CURSOR_HOME,FXText::onCmdCursorHome),
  FXMAPFUNC(SEL_COMMAND,FXText::ID_CURSOR_END,FXText::onCmdCursorEnd),
  FXMAPFUNC(SEL_COMMAND,FXText::ID_CURSOR_RIGHT,FXText::onCmdCursorRight),
  FXMAPFUNC(SEL_COMMAND,FXText::ID_CURSOR_LEFT,FXText::onCmdCursorLeft),
  FXMAPFUNC(SEL_COMMAND,FXText::ID_CURSOR_UP,FXText::onCmdCursorUp),
  FXMAPFUNC(SEL_COMMAND,FXText::ID_CURSOR_DOWN,FXText::onCmdCursorDown),
  FXMAPFUNC(SEL_COMMAND,FXText::ID_CURSOR_PAGEUP,FXText::onCmdCursorPageUp),
  FXMAPFUNC(SEL_COMMAND,FXText::ID_CURSOR_PAGEDOWN,FXText::onCmdCursorPageDown),
  FXMAPFUNC(SEL_COMMAND,FXText::ID_CURSOR_WORD_LEFT,FXText::onCmdCursorWordLeft),
  FXMAPFUNC(SEL_COMMAND,FXText::ID_CURSOR_WORD_RIGHT,FXText::onCmdCursorWordRight),
  FXMAPFUNC(SEL_COMMAND,FXText::ID_CURSOR_SEL_START,FXText::onCmdCursorSelStart),
  FXMAPFUNC(SEL_COMMAND,FXText::ID_CURSOR_SEL_END,FXText::onCmdCursorSelEnd),
  FXMAPFUNC(SEL_COMMAND,FXText::ID_CURSOR_SHIFT_TOP,FXText::onCmdCursorShiftTop),
  FXMAPFUNC(SEL_COMMAND,FXText::ID_CURSOR_SHIFT_BOTTOM,FXText::onCmdCursorShiftBottom),
  FXMAPFUNC(SEL_COMMAND,FXText::ID_CURSOR_SHIFT_HOME,FXText::onCmdCursorShiftHome),
  FXMAPFUNC(SEL_COMMAND,FXText::ID_CURSOR_SHIFT_END,FXText::onCmdCursorShiftEnd),
  FXMAPFUNC(SEL_COMMAND,FXText::ID_CURSOR_SHIFT_RIGHT,FXText::onCmdCursorShiftRight),
  FXMAPFUNC(SEL_COMMAND,FXText::ID_CURSOR_SHIFT_LEFT,FXText::onCmdCursorShiftLeft),
  FXMAPFUNC(SEL_COMMAND,FXText::ID_CURSOR_SHIFT_UP,FXText::onCmdCursorShiftUp),
  FXMAPFUNC(SEL_COMMAND,FXText::ID_CURSOR_SHIFT_DOWN,FXText::onCmdCursorShiftDown),
  FXMAPFUNC(SEL_COMMAND,FXText::ID_CURSOR_SHIFT_PAGEUP,FXText::onCmdCursorShiftPageUp),
  FXMAPFUNC(SEL_COMMAND,FXText::ID_CURSOR_SHIFT_PAGEDOWN,FXText::onCmdCursorShiftPageDown),
  FXMAPFUNC(SEL_COMMAND,FXText::ID_CURSOR_SHIFT_WORD_LEFT,FXText::onCmdCursorShiftWordLeft),
  FXMAPFUNC(SEL_COMMAND,FXText::ID_CURSOR_SHIFT_WORD_RIGHT,FXText::onCmdCursorShiftWordRight),
  FXMAPFUNC(SEL_COMMAND,FXText::ID_SCROLL_UP,FXText::onCmdScrollUp),
  FXMAPFUNC(SEL_COMMAND,FXText::ID_SCROLL_DOWN,FXText::onCmdScrollDown),
  FXMAPFUNC(SEL_COMMAND,FXText::ID_SCROLL_TOP,FXText::onCmdScrollTop),
  FXMAPFUNC(SEL_COMMAND,FXText::ID_SCROLL_BOTTOM,FXText::onCmdScrollBottom),
  FXMAPFUNC(SEL_COMMAND,FXText::ID_SCROLL_CENTER,FXText::onCmdScrollCenter),
  FXMAPFUNC(SEL_COMMAND,FXText::ID_INSERT_STRING,FXText::onCmdInsertString),
  FXMAPFUNC(SEL_COMMAND,FXText::ID_INSERT_NEWLINE,FXText::onCmdInsertNewline),
  FXMAPFUNC(SEL_COMMAND,FXText::ID_INSERT_NEWLINE_ONLY,FXText::onCmdInsertNewlineOnly),
  FXMAPFUNC(SEL_COMMAND,FXText::ID_INSERT_NEWLINE_INDENT,FXText::onCmdInsertNewlineIndent),
  FXMAPFUNC(SEL_COMMAND,FXText::ID_INSERT_TAB,FXText::onCmdInsertTab),
  FXMAPFUNC(SEL_COMMAND,FXText::ID_INSERT_HARDTAB,FXText::onCmdInsertHardTab),
  FXMAPFUNC(SEL_COMMAND,FXText::ID_INSERT_SOFTTAB,FXText::onCmdInsertSoftTab),
  FXMAPFUNC(SEL_COMMAND,FXText::ID_CUT_SEL,FXText::onCmdCutSel),
  FXMAPFUNC(SEL_COMMAND,FXText::ID_COPY_SEL,FXText::onCmdCopySel),
  FXMAPFUNC(SEL_COMMAND,FXText::ID_DELETE_SEL,FXText::onCmdDeleteSel),
  FXMAPFUNC(SEL_COMMAND,FXText::ID_REPLACE_SEL,FXText::onCmdReplaceSel),
  FXMAPFUNC(SEL_COMMAND,FXText::ID_PASTE_SEL,FXText::onCmdPasteSel),
  FXMAPFUNC(SEL_COMMAND,FXText::ID_PASTE_MIDDLE,FXText::onCmdPasteMiddle),
  FXMAPFUNC(SEL_COMMAND,FXText::ID_SELECT_CHAR,FXText::onCmdSelectChar),
  FXMAPFUNC(SEL_COMMAND,FXText::ID_SELECT_WORD,FXText::onCmdSelectWord),
  FXMAPFUNC(SEL_COMMAND,FXText::ID_SELECT_LINE,FXText::onCmdSelectLine),
  FXMAPFUNC(SEL_COMMAND,FXText::ID_SELECT_ALL,FXText::onCmdSelectAll),
  FXMAPFUNC(SEL_COMMAND,FXText::ID_DESELECT_ALL,FXText::onCmdDeselectAll),
  FXMAPFUNC(SEL_COMMAND,FXText::ID_BACKSPACE_CHAR,FXText::onCmdBackspaceChar),
  FXMAPFUNC(SEL_COMMAND,FXText::ID_BACKSPACE_WORD,FXText::onCmdBackspaceWord),
  FXMAPFUNC(SEL_COMMAND,FXText::ID_BACKSPACE_BOL,FXText::onCmdBackspaceBol),
  FXMAPFUNC(SEL_COMMAND,FXText::ID_DELETE_CHAR,FXText::onCmdDeleteChar),
  FXMAPFUNC(SEL_COMMAND,FXText::ID_DELETE_WORD,FXText::onCmdDeleteWord),
  FXMAPFUNC(SEL_COMMAND,FXText::ID_DELETE_EOL,FXText::onCmdDeleteEol),
  FXMAPFUNC(SEL_COMMAND,FXText::ID_DELETE_ALL,FXText::onCmdDeleteAll),
  FXMAPFUNC(SEL_COMMAND,FXText::ID_DELETE_LINE,FXText::onCmdDeleteLine),
  FXMAPFUNC(SEL_COMMAND,FXText::ID_TOGGLE_EDITABLE,FXText::onCmdToggleEditable),
  FXMAPFUNC(SEL_COMMAND,FXText::ID_TOGGLE_OVERSTRIKE,FXText::onCmdToggleOverstrike),
  FXMAPFUNC(SEL_COMMAND,FXText::ID_CURSOR_ROW,FXText::onCmdCursorRow),
  FXMAPFUNC(SEL_COMMAND,FXText::ID_CURSOR_COLUMN,FXText::onCmdCursorColumn),
  FXMAPFUNC(SEL_COMMAND,FXText::ID_SETSTRINGVALUE,FXText::onCmdSetStringValue),
  FXMAPFUNC(SEL_COMMAND,FXText::ID_GETSTRINGVALUE,FXText::onCmdGetStringValue),
  FXMAPFUNC(SEL_COMMAND,FXText::ID_UPPER_CASE,FXText::onCmdChangeCase),
  FXMAPFUNC(SEL_COMMAND,FXText::ID_LOWER_CASE,FXText::onCmdChangeCase),
  FXMAPFUNC(SEL_COMMAND,FXText::ID_JOIN_LINES,FXText::onCmdJoinLines),
  FXMAPFUNC(SEL_COMMAND,FXText::ID_GOTO_MATCHING,FXText::onCmdGotoMatching),
  FXMAPFUNC(SEL_COMMAND,FXText::ID_SELECT_MATCHING,FXText::onCmdSelectMatching),
  FXMAPFUNCS(SEL_COMMAND,FXText::ID_SELECT_BRACE,FXText::ID_SELECT_ANG,FXText::onCmdSelectBlock),
  FXMAPFUNCS(SEL_COMMAND,FXText::ID_LEFT_BRACE,FXText::ID_LEFT_ANG,FXText::onCmdBlockBeg),
  FXMAPFUNCS(SEL_COMMAND,FXText::ID_RIGHT_BRACE,FXText::ID_RIGHT_ANG,FXText::onCmdBlockEnd),
  FXMAPFUNCS(SEL_COMMAND,FXText::ID_SHIFT_LEFT,FXText::ID_SHIFT_TABRIGHT,FXText::onCmdShiftText),
  FXMAPFUNC(SEL_COMMAND,FXText::ID_CLEAN_INDENT,FXText::onCmdShiftText),
  FXMAPFUNC(SEL_COMMAND,FXText::ID_SETHELPSTRING,FXText::onCmdSetHelp),
  FXMAPFUNC(SEL_COMMAND,FXText::ID_GETHELPSTRING,FXText::onCmdGetHelp),
  FXMAPFUNC(SEL_COMMAND,FXText::ID_SETTIPSTRING,FXText::onCmdSetTip),
  FXMAPFUNC(SEL_COMMAND,FXText::ID_GETTIPSTRING,FXText::onCmdGetTip),
  };


// Object implementation
FXIMPLEMENT(FXText,FXScrollArea,FXTextMap,ARRAYNUMBER(FXTextMap))


// Delimiters
const FXchar FXText::textDelimiters[]="~.,/\\`'!@#$%^&*()-=+{}|[]\":;<>?";

// Matching things
static const FXchar lefthand[]="{[(<";
static const FXchar righthand[]="}])>";

// Spaces, lots of spaces
static const FXchar spaces[MAXTABCOLUMNS+1]="                                ";

/*******************************************************************************/


// Absolute value
static inline FXint fxabs(FXint a){ return a<0?-a:a; }


// For deserialization
FXText::FXText(){
  flags|=FLAG_ENABLED|FLAG_DROPTARGET;
  buffer=NULL;
  sbuffer=NULL;
  visrows=NULL;
  length=0;
  nvisrows=0;
  nrows=1;
  gapstart=0;
  gapend=0;
  toppos=0;
  toprow=0;
  keeppos=0;
  selstartpos=0;
  selendpos=0;
  hilitestartpos=0;
  hiliteendpos=0;
  anchorpos=0;
  cursorpos=0;
  cursorstartpos=0;
  cursorendpos=0;
  cursorrow=0;
  cursorcol=0;
  prefcol=-1;
  margintop=0;
  marginbottom=0;
  marginleft=0;
  marginright=0;
  wrapwidth=80;
  wrapcolumns=80;
  tabwidth=8;
  tabcolumns=8;
  barwidth=0;
  barcolumns=0;
  font=NULL;
  textColor=0;
  selbackColor=0;
  seltextColor=0;
  hilitebackColor=0;
  hilitetextColor=0;
  activebackColor=0;
  numberColor=0;
  cursorColor=0;
  barColor=0;
  textWidth=0;
  textHeight=0;
  delimiters=textDelimiters;
  vrows=0;
  vcols=0;
  hilitestyles=NULL;
  matchtime=0;
  grabx=0;
  graby=0;
  mode=MOUSE_NONE;
  modified=false;
  }


// Text widget
FXText::FXText(FXComposite *p,FXObject* tgt,FXSelector sel,FXuint opts,FXint x,FXint y,FXint w,FXint h,FXint pl,FXint pr,FXint pt,FXint pb):FXScrollArea(p,opts,x,y,w,h){
  flags|=FLAG_ENABLED|FLAG_DROPTARGET;
  target=tgt;
  message=sel;
  callocElms(buffer,MINSIZE);
  sbuffer=NULL;
  callocElms(visrows,NVISROWS+1);
  length=0;
  nrows=1;
  nvisrows=NVISROWS;
  gapstart=0;
  gapend=MINSIZE;
  toppos=0;
  toprow=0;
  keeppos=0;
  selstartpos=0;
  selendpos=0;
  hilitestartpos=0;
  hiliteendpos=0;
  anchorpos=0;
  cursorpos=0;
  cursorstartpos=0;
  cursorendpos=0;
  cursorrow=0;
  cursorcol=0;
  prefcol=-1;
  margintop=pt;
  marginbottom=pb;
  marginleft=pl;
  marginright=pr;
  wrapwidth=80;
  wrapcolumns=80;
  tabwidth=8;
  tabcolumns=8;
  barwidth=0;
  barcolumns=0;
  font=getApp()->getNormalFont();
  hilitestyles=NULL;
  defaultCursor=getApp()->getDefaultCursor(DEF_TEXT_CURSOR);
  dragCursor=getApp()->getDefaultCursor(DEF_TEXT_CURSOR);
  textColor=getApp()->getForeColor();
  selbackColor=getApp()->getSelbackColor();
  seltextColor=getApp()->getSelforeColor();
  hilitebackColor=FXRGB(255,128,128);
  hilitetextColor=getApp()->getForeColor();
  activebackColor=backColor;
  numberColor=textColor;
  cursorColor=getApp()->getForeColor();
  barColor=backColor;
  textWidth=0;
  textHeight=0;
  delimiters=textDelimiters;
  vrows=0;
  vcols=0;
  matchtime=0;
  grabx=0;
  graby=0;
  mode=MOUSE_NONE;
  modified=false;
  }


// Create window
void FXText::create(){
  FXScrollArea::create();
  font->create();
  tabwidth=tabcolumns*font->getTextWidth(" ",1);
  barwidth=barcolumns*font->getTextWidth("8",1);
  recalc();
  if(getApp()->hasInputMethod()){
    createComposeContext();
    getComposeContext()->setFont(font);
    }
  }


// Detach window
void FXText::detach(){
  FXScrollArea::detach();
  font->detach();
  }


// Get default width
FXint FXText::getDefaultWidth(){
  return 0<vcols ? marginleft+marginright+vcols*font->getTextWidth("8",1)+barwidth : FXScrollArea::getDefaultWidth()+barwidth;
  }


// Get default height
FXint FXText::getDefaultHeight(){
  return 0<vrows ? margintop+marginbottom+vrows*font->getFontHeight() : FXScrollArea::getDefaultHeight();
  }


// If window can have focus
FXbool FXText::canFocus() const {
  return true;
  }


// Into focus chain
void FXText::setFocus(){
  FXScrollArea::setFocus();
  setDefault(true);
  flags&=~FLAG_UPDATE;
  if(getApp()->hasInputMethod()){
    createComposeContext();
    getComposeContext()->setFont(font);
    }
  }


// Out of focus chain
void FXText::killFocus(){
  FXScrollArea::killFocus();
  setDefault(maybe);
  flags|=FLAG_UPDATE;
  if(getApp()->hasInputMethod()){
    destroyComposeContext();
    }
  }


// Enable the window
void FXText::enable(){
  if(!(flags&FLAG_ENABLED)){
    FXScrollArea::enable();
    update(0,0,width,height);
    }
  }


// Disable the window
void FXText::disable(){
  if(flags&FLAG_ENABLED){
    FXScrollArea::disable();
    update(0,0,width,height);
    }
  }


// Propagate size change
void FXText::recalc(){
  FXScrollArea::recalc();
  flags|=FLAG_RECALC;
  }

/*******************************************************************************/

// See if position is in the selection, and the selection is non-empty
FXbool FXText::isPosSelected(FXint pos) const {
  return selstartpos<selendpos && selstartpos<=pos && pos<=selendpos;
  }


// Check if w is delimiter
static FXbool isdelimiter(const FXchar *delimiters,FXwchar w){
  return w<128 && strchr(delimiters,w); // FIXME for w>=128
  }

// Make a valid position, at the start of a wide character
FXint FXText::validPos(FXint pos) const {
  const FXchar* ptr=&buffer[(gapend-gapstart)&((~pos+gapstart)>>31)];
  if(pos<=0) return 0;
  if(pos>=length) return length;
  return (FXISUTF8(ptr[pos]) || --pos<=0 || FXISUTF8(ptr[pos]) || --pos<=0 || FXISUTF8(ptr[pos]) || --pos), pos;
  }


// Decrement; a wide character does not cross the gap, so if pos is at
// or below below the gap, we read from the segment below the gap
FXint FXText::dec(FXint pos) const {
  const FXchar* ptr=&buffer[(gapend-gapstart)&((gapstart-pos)>>31)];
  return (--pos<=0 || FXISUTF8(ptr[pos]) || --pos<=0 || FXISUTF8(ptr[pos]) || --pos<=0 || FXISUTF8(ptr[pos]) || --pos), pos;
  }


// Increment; since a wide character does not cross the gap, if we
// start under the gap the last character accessed is below the gap
FXint FXText::inc(FXint pos) const {
  const FXchar* ptr=&buffer[(gapend-gapstart)&((~pos+gapstart)>>31)];
  return (++pos>=length || FXISUTF8(ptr[pos]) || ++pos>=length || FXISUTF8(ptr[pos]) || ++pos>=length || FXISUTF8(ptr[pos]) || ++pos), pos;
  }


// Get byte
FXint FXText::getByte(FXint pos) const {
  return (FXuchar)buffer[pos+((gapend-gapstart)&((~pos+gapstart)>>31))];
  }


// Get character, assuming that gap never inside utf8 encoding
FXwchar FXText::getChar(FXint pos) const {
  FXASSERT(0<=pos && pos<length);
  const FXuchar* ptr=(FXuchar*)&buffer[pos+((gapend-gapstart)&((~pos+gapstart)>>31))];
  FXwchar w=ptr[0];
  if(__unlikely(0xC0<=w)){ w=(w<<6)^ptr[1]^0x3080;
  if(__unlikely(0x800<=w)){ w=(w<<6)^ptr[2]^0x20080;
  if(__unlikely(0x10000<=w)){ w=(w<<6)^ptr[3]^0x400080; }}}
  return w;
  }


// Get length of wide character at position pos
FXint FXText::getCharLen(FXint pos) const {
  FXASSERT(0<=pos && pos<length);
  return FXString::utfBytes[(FXuchar)buffer[pos+((gapend-gapstart)&((~pos+gapstart)>>31))]];
  }


// Get style
FXint FXText::getStyle(FXint pos) const {
  FXASSERT(0<=pos && pos<length);
  return (FXuchar)sbuffer[pos+((gapend-gapstart)&((~pos+gapstart)>>31))];
  }


// Move the gap; gap is never moved inside utf character
void FXText::movegap(FXint pos){
  register FXint gaplen=gapend-gapstart;
  FXASSERT(0<=pos && pos<=length);
  FXASSERT(0<=gapstart && gapstart<=length);
  if(gapstart<pos){
    memmove(&buffer[gapstart],&buffer[gapend],pos-gapstart);
    if(sbuffer){memmove(&sbuffer[gapstart],&sbuffer[gapend],pos-gapstart);}
    gapend=pos+gaplen;
    gapstart=pos;
    }
  else if(pos<gapstart){
    memmove(&buffer[pos+gaplen],&buffer[pos],gapstart-pos);
    if(sbuffer){memmove(&sbuffer[pos+gaplen],&sbuffer[pos],gapstart-pos);}
    gapend=pos+gaplen;
    gapstart=pos;
    }
  }


// Size gap
void FXText::sizegap(FXint sz){
  register FXint gaplen=gapend-gapstart;
  FXASSERT(0<=gapstart && gapstart<=length);
  if(sz>=gaplen){
    sz+=MINSIZE;
    if(!resizeElms(buffer,length+sz)){
      fxerror("%s::sizegap: out of memory.\n",getClassName());
      }
    memmove(&buffer[gapstart+sz],&buffer[gapend],length-gapstart);
    if(sbuffer){
      if(!resizeElms(sbuffer,length+sz)){
        fxerror("%s::sizegap: out of memory.\n",getClassName());
        }
      memmove(&sbuffer[gapstart+sz],&sbuffer[gapend],length-gapstart);
      }
    gapend=gapstart+sz;
    }
  }


// Squeeze out the gap by moving it to the end of the buffer
void FXText::squeezegap(){
  if(gapstart!=length){
    memmove(&buffer[gapstart],&buffer[gapend],length-gapstart);
    if(sbuffer){memmove(&sbuffer[gapstart],&sbuffer[gapend],length-gapstart);}
    gapend=length+gapend-gapstart;
    gapstart=length;
    }
  }

/*******************************************************************************/

// FIXME
// Its a little bit more complex than this:
// We need to deal with diacritics, i.e. non-spacing stuff.  When wrapping, scan till
// the next starter-character [the one with charCombining(c)==0].  Then measure the
// string from that point on. This means FXFont::getCharWidth() is really quite useless.
// Next, we also have the issue of ligatures [fi, AE] and kerning-pairs [VA].
// With possible kerning pairs, we should really measure stuff from the start of the
// line [but this is *very* expensive!!].  We may want to just back up a few characters;
// perhaps to the start of the word, or just the previous character, if not a space.
// Need to investigate this some more; for now assume Normalization Form C.

// Character width
FXint FXText::charWidth(FXwchar ch,FXint indent) const {
  if(__likely(' '<=ch)) return font->getCharWidth(ch);
  if(__likely(ch=='\t')) return (tabwidth-indent%tabwidth);
  return font->getCharWidth('^')+font->getCharWidth(ch|0x40);
  }


// FIXME
// Special codes for non-breaking space U+00A0, zero-width space (U+200B), non-breaking
// hyphen (U+2011), and other line break types.

// Start of next wrapped line
FXint FXText::wrap(FXint start) const {
  register FXint lw,cw,p,s,c;
  FXASSERT(0<=start && start<=length);
  lw=0;
  p=s=start;
  while(p<length){
    c=getChar(p);
    if(c=='\n') return p+1;     // Newline always breaks
    cw=charWidth(c,lw);
    if(lw+cw>wrapwidth){        // Technically, a tab-before-wrap should be as wide as space!
      if(s>start) return s;     // We remembered the last space we encountered; break there!
      if(p==start) p++;         // Always at least one character on each line!
      return p;
      }
    lw+=cw;
    p+=getCharLen(p);
    if(Unicode::isSpace(c)) s=p;// Remember potential break point!
    }
  return length;
  }


// Count number of newlines
FXint FXText::countLines(FXint start,FXint end) const {
  register FXint p=start,nl=0;
  FXASSERT(0<=start && end<=length+1);
  while(p<end){
    if(p>=length) return nl+1;
    if(getByte(p)=='\n') nl++;
    p++;
    }
  return nl;
  }


// Count number of rows; start should be on a row start
FXint FXText::countRows(FXint start,FXint end) const {
  register FXint p,q,s,c,cw,w=0,nr=0;
  FXASSERT(0<=start && end<=length+1);
  if(options&TEXT_WORDWRAP){
    p=q=s=start;
    while(q<end){
      if(p>=length) return nr+1;
      c=getChar(p);
      if(c=='\n'){                      // Break at newline
        nr++;
        w=0;
        p=q=s=p+1;
        continue;
        }
      cw=charWidth(c,w);
      if(w+cw>wrapwidth){               // Break due to wrap
        nr++;
        w=0;
        if(s>q){                        // Break past last space seen
          p=q=s;
          continue;
          }
        if(p==q) p+=getCharLen(p);      // Break anywhere, but at least one character on each line
        q=s=p;
        continue;
        }
      w+=cw;
      p+=getCharLen(p);
      if(Unicode::isSpace(c)) s=p;
      }
    }
  else{
    p=start;
    while(p<end){
      if(p>=length) return nr+1;
      c=getByte(p);
      if(c=='\n') nr++;
      p++;
      }
    }
  return nr;
  }


// Count number of columns; start should be on a row start
FXint FXText::countCols(FXint start,FXint end) const {
  register FXint nc=0,in=0,ch;
  FXASSERT(0<=start && end<=length);
  while(start<end){
    ch=getChar(start);
    if(ch=='\n'){
      if(in>nc) nc=in;
      in=0;
      }
    else if(ch=='\t'){
      in+=(tabcolumns-nc%tabcolumns);
      }
    else{
      in++;
      }
    start+=getCharLen(start);
    }
  if(in>nc) nc=in;
  return nc;
  }


// Measure lines; start and end should be on a row start
FXint FXText::measureText(FXint start,FXint end,FXint& wmax,FXint& hmax) const {
  register FXint nr=0,w=0,c,cw,p,q,s;
  FXASSERT(0<=start && end<=length+1);
  if(options&TEXT_WORDWRAP){
    wmax=wrapwidth;
    p=q=s=start;
    while(q<end){
      if(p>=length){
        nr++;
        break;
        }
      c=getChar(p);
      if(c=='\n'){                      // Break at newline
        nr++;
        w=0;
        p=q=s=p+1;
        continue;
        }
      cw=charWidth(c,w);
      if(w+cw>wrapwidth){               // Break due to wrap
        nr++;
        w=0;
        if(s>q){                        // Break past last space seen
          p=q=s;
          continue;
          }
        if(p==q) p+=getCharLen(p);      // Break anywhere, but at least one character on each line
        q=s=p;
        continue;
        }
      w+=cw;
      p+=getCharLen(p);
      if(Unicode::isSpace(c)) s=p;
      }
    }
  else{
    wmax=0;
    p=start;
    while(p<end){
      if(p>=length){
        if(w>wmax) wmax=w;
        nr++;
        break;
        }
      c=getChar(p);
      if(c=='\n'){                      // Break at newline
        if(w>wmax) wmax=w;
        nr++;
        w=0;
        }
      else{
        w+=charWidth(c,w);
        }
      p+=getCharLen(p);
      }
    }
  hmax=nr*font->getFontHeight();
  return nr;
  }


// Find end of previous word
FXint FXText::leftWord(FXint pos) const {
  register FXint ch;
  FXASSERT(0<=pos && pos<=length);
  if(0<pos){
    pos=dec(pos);
    ch=getChar(pos);
    if(isdelimiter(delimiters,ch)){
      while(0<pos){
        ch=getChar(dec(pos));
        if(Unicode::isSpace(ch) || !isdelimiter(delimiters,ch)) return pos;
        pos=dec(pos);
        }
      }
    else if(!Unicode::isSpace(ch)){
      while(0<pos){
        ch=getChar(dec(pos));
        if(Unicode::isSpace(ch) || isdelimiter(delimiters,ch)) return pos;
        pos=dec(pos);
        }
      }
    while(0<pos){
      ch=getChar(dec(pos));
      if(!Unicode::isBlank(ch)) return pos;
      pos=dec(pos);
      }
    }
  return pos;
  }


// Find begin of next word
FXint FXText::rightWord(FXint pos) const {
  register FXint ch;
  FXASSERT(0<=pos && pos<=length);
  if(pos<length){
    ch=getChar(pos);
    pos=inc(pos);
    if(isdelimiter(delimiters,ch)){
      while(pos<length){
        ch=getChar(pos);
        if(Unicode::isSpace(ch) || !isdelimiter(delimiters,ch)) return pos;
        pos=inc(pos);
        }
      }
    else if(!Unicode::isSpace(ch)){
      while(pos<length){
        ch=getChar(pos);
        if(Unicode::isSpace(ch) || isdelimiter(delimiters,ch)) return pos;
        pos=inc(pos);
        }
      }
    while(pos<length){
      ch=getChar(pos);
      if(!Unicode::isBlank(ch)) return pos;
      pos=inc(pos);
      }
    }
  return pos;
  }


// Find begin of a word
FXint FXText::wordStart(FXint pos) const {
  FXASSERT(0<=pos && pos<=length);
  if(0<pos){
    FXint ch=(pos<length)?getChar(pos):' ';
    if(ch=='\n') return pos;
    if(Unicode::isBlank(ch)){
      while(0<pos){
        ch=getChar(dec(pos));
        if(!Unicode::isBlank(ch)) return pos;
        pos=dec(pos);
        }
      }
    else if(isdelimiter(delimiters,ch)){
      while(0<pos){
        ch=getChar(dec(pos));
        if(!isdelimiter(delimiters,ch)) return pos;
        pos=dec(pos);
        }
      }
    else{
      while(0<pos){
        ch=getChar(dec(pos));
        if(isdelimiter(delimiters,ch) || Unicode::isSpace(ch)) return pos;
        pos=dec(pos);
        }
      }
    }
  return pos;
  }


// Find end of word
FXint FXText::wordEnd(FXint pos) const {
  FXASSERT(0<=pos && pos<=length);
  if(pos<length){
    FXint ch=getChar(pos);
    if(ch=='\n') return pos+1;
    if(Unicode::isBlank(ch)){
      while(pos<length){
        ch=getChar(pos);
        if(!Unicode::isBlank(ch)) return pos;
        pos=inc(pos);
        }
      }
    else if(isdelimiter(delimiters,ch)){
      while(pos<length){
        ch=getChar(pos);
        if(!isdelimiter(delimiters,ch)) return pos;
        pos=inc(pos);
        }
      }
    else{
      while(pos<length){
        ch=getChar(pos);
        if(isdelimiter(delimiters,ch) || Unicode::isSpace(ch)) return pos;
        pos=inc(pos);
        }
      }
    }
  return pos;
  }


// Return position of begin of paragraph
FXint FXText::lineStart(FXint pos) const {
  FXASSERT(0<=pos && pos<=length);
  while(0<pos){ if(getByte(pos-1)=='\n') return pos; pos--; }
  return 0;
  }


// Return position of end of paragraph
FXint FXText::lineEnd(FXint pos) const {
  FXASSERT(0<=pos && pos<=length);
  while(pos<length){ if(getByte(pos)=='\n') return pos; pos++; }
  return length;
  }


// Return start of next line
FXint FXText::nextLine(FXint pos,FXint nl) const {
  FXASSERT(0<=pos && pos<=length);
  if(nl<=0) return pos;
  while(pos<length){
    if(getByte(pos)=='\n' && --nl==0) return pos+1;
    pos++;
    }
  return length;
  }


// Return start of previous line
FXint FXText::prevLine(FXint pos,FXint nl) const {
  FXASSERT(0<=pos && pos<=length);
  if(nl<=0) return pos;
  while(0<pos){
    if(getByte(pos-1)=='\n' && nl--==0) return pos;
    pos--;
    }
  return 0;
  }


// Return row start
FXint FXText::rowStart(FXint pos) const {
  register FXint p,t;
  FXASSERT(0<=pos && pos<=length);
  p=lineStart(pos);
  if(!(options&TEXT_WORDWRAP)) return p;
  while(p<pos && (t=wrap(p))<=pos && t<length) p=t;
  FXASSERT(0<=p && p<=pos);
  return p;
  }


// Return row end
FXint FXText::rowEnd(FXint pos) const {
  register FXint p;
  FXASSERT(0<=pos && pos<=length);
  if(!(options&TEXT_WORDWRAP)) return lineEnd(pos);
  p=lineStart(pos);
  while(p<length && p<=pos) p=wrap(p);
  FXASSERT(0<=p && p<=length);
  if(pos<p && Unicode::isSpace(getChar(dec(p)))) p=dec(p);
  FXASSERT(pos<=p && p<=length);
  return p;
  }


// Move to next row given start of line
FXint FXText::nextRow(FXint pos,FXint nr) const {
  register FXint p;
  FXASSERT(0<=pos && pos<=length);
  if(!(options&TEXT_WORDWRAP)) return nextLine(pos,nr);
  if(nr<=0) return pos;
  p=rowStart(pos);
  while(p<length && 0<nr){ p=wrap(p); nr--; }
  FXASSERT(0<=p && p<=length);
  return p;
  }


// Move to previous row given start of line
FXint FXText::prevRow(FXint pos,FXint nr) const {
  register FXint p,q,t;
  FXASSERT(0<=pos && pos<=length);
  if(!(options&TEXT_WORDWRAP)) return prevLine(pos,nr);
  if(nr<=0) return pos;
  while(0<pos){
    p=lineStart(pos);
    for(q=p; q<pos && (t=wrap(q))<=pos && t<length; q=t) nr--;
    if(nr==0) return p;
    if(nr<0){
      do{p=wrap(p);}while(++nr);
      FXASSERT(0<=p && p<=length);
      return p;
      }
    pos=p-1;
    nr--;
    }
  return 0;
  }


// Backs up to the begin of the line preceding the line containing pos, or the
// start of the line containing pos if the preceding line terminated in a newline
FXint FXText::changeBeg(FXint pos) const {
  register FXint p1,p2,t;
  FXASSERT(0<=pos && pos<=length);
  p1=p2=lineStart(pos);
  if(options&TEXT_WORDWRAP){
    while(p2<pos && (t=wrap(p2))<=pos){
      p1=p2;
      p2=t;
      }
    }
  FXASSERT(0<=p1 && p1<=length);
  return p1;
  }


// Scan forward to the end of affected area, which is the start of the next
// paragraph; a change can cause the rest of the paragraph to reflow.
FXint FXText::changeEnd(FXint pos) const {
  FXASSERT(0<=pos && pos<=length);
  while(pos<length){
    if(getByte(pos)=='\n') return pos+1;
    pos++;
    }
  return length+1;  // YES, one more!
  }


// Calculate line width
FXint FXText::lineWidth(FXint pos,FXint n) const {
  register FXint end=pos+n,w=0;
  FXASSERT(0<=pos && end<=length);
  while(pos<end){ w+=charWidth(getChar(pos),w); pos+=getCharLen(pos); }
  return w;
  }


// Determine indent of position pos relative to start
FXint FXText::indentFromPos(FXint start,FXint pos) const {
  register FXint p=start,in=0;
  register FXwchar c;
  FXASSERT(0<=start && pos<=length);
  while(p<pos){
    c=getChar(p);
    if(c=='\n'){
      in=0;
      }
    else if(c=='\t'){
      in+=(tabcolumns-in%tabcolumns);
      }
    else{
      in+=1;
      }
    p+=getCharLen(p);
    }
  return in;
  }


// Determine position of indent relative to start
FXint FXText::posFromIndent(FXint start,FXint indent) const {
  register FXint pos=start,in=0;
  register FXwchar c;
  FXASSERT(0<=start && start<=length);
  while(in<indent && pos<length){
    c=getChar(pos);
    if(c=='\n'){
      break;
      }
    else if(c=='\t'){
      in+=(tabcolumns-in%tabcolumns);
      }
    else{
      in+=1;
      }
    pos+=getCharLen(pos);
    }
  return pos;
  }


// Search forward for match
FXint FXText::matchForward(FXint pos,FXint end,FXwchar l,FXwchar r,FXint level) const {
  register FXwchar c;
  FXASSERT(0<=end && end<=length);
  FXASSERT(0<=pos && pos<=length);
  while(pos<end){
    c=getChar(pos);
    if(c==r){
      level--;
      if(level<=0) return pos;
      }
    else if(c==l){
      level++;
      }
    pos=inc(pos);
    }
  return -1;
  }


// Search backward for match
FXint FXText::matchBackward(FXint pos,FXint beg,FXwchar l,FXwchar r,FXint level) const {
  register FXwchar c;
  FXASSERT(0<=beg && beg<=length);
  FXASSERT(0<=pos && pos<=length);
  while(beg<=pos){
    c=getChar(pos);
    if(c==l){
      level--;
      if(level<=0) return pos;
      }
    else if(c==r){
      level++;
      }
    pos=dec(pos);
    }
  return -1;
  }


// Search for matching character
FXint FXText::findMatching(FXint pos,FXint beg,FXint end,FXwchar ch,FXint level) const {
  FXASSERT(0<=level);
  FXASSERT(0<=pos && pos<=length);
  switch(ch){
    case '{': return matchForward(pos+1,end,'{','}',level);
    case '}': return matchBackward(pos-1,beg,'{','}',level);
    case '[': return matchForward(pos+1,end,'[',']',level);
    case ']': return matchBackward(pos-1,beg,'[',']',level);
    case '(': return matchForward(pos+1,end,'(',')',level);
    case ')': return matchBackward(pos-1,beg,'(',')',level);
    }
  return -1;
  }


// Flash matching braces or parentheses, if within visible part of buffer
void FXText::flashMatching(){
  FXint matchpos;
  killHighlight();
  getApp()->removeTimeout(this,ID_FLASH);
  if(0<matchtime && 0<cursorpos){
    matchpos=findMatching(cursorpos-1,visrows[0],visrows[nvisrows],getByte(cursorpos-1),1);
    if(0<=matchpos){
      getApp()->addTimeout(this,ID_FLASH,matchtime);
      setHighlight(matchpos,1);
      }
    }
  }


// Shift text by certain amount
FXint FXText::shiftText(FXint start,FXint end,FXint amount,FXbool notify){
  FXint white,p,len,size,c;
  FXchar *text;
  if(start<0) start=0;
  if(end>length) end=length;
  FXASSERT(0<tabcolumns && tabcolumns<MAXTABCOLUMNS);
  if(start<end){
    p=start;
    white=0;
    size=0;
    while(p<end){               // FIXME fix for UTF8
      c=getByte(p++);
      if(c==' '){
        white++;
        }
      else if(c=='\t'){
        white+=(tabcolumns-white%tabcolumns);
        }
      else if(c=='\n'){
        size++; white=0;
        }
      else{
        white+=amount;
        if(white<0) white=0;
        if(!(options&TEXT_NO_TABS)){ size+=(white/tabcolumns+white%tabcolumns); } else { size+=white; }
        size++;
        while(p<end){
          c=getByte(p++);
          size++;
          if(c=='\n') break;
          }
        white=0;
        }
      }
    allocElms(text,size);
    p=start;
    white=0;
    len=0;
    while(p<end){
      c=getByte(p++);
      if(c==' '){
        white++;
        }
      else if(c=='\t'){
        white+=(tabcolumns-white%tabcolumns);
        }
      else if(c=='\n'){
        text[len++]='\n'; white=0;
        }
      else{
        white+=amount;
        if(white<0) white=0;
        if(!(options&TEXT_NO_TABS)){ while(white>=tabcolumns){ text[len++]='\t'; white-=tabcolumns;} }
        while(white>0){ text[len++]=' '; white--; }
        text[len++]=c;
        while(p<end){
          c=getByte(p++);
          text[len++]=c;
          if(c=='\n') break;
          }
        white=0;
        }
      }
    FXASSERT(len<=size);
    replaceText(start,end-start,text,len,notify);
    freeElms(text);
    return len;
    }
  return 0;
  }


// Search for text
FXbool FXText::findText(const FXString& string,FXint* beg,FXint* end,FXint start,FXuint flgs,FXint npar){
  FXint rexmode=FXRex::Normal;
  FXRex rex;

  // Check arguments
  if(npar<1 || !beg || !end){ fxerror("%s::findText: bad argument.\n",getClassName()); }

  // Tweak parse flags a bit
  if(1<npar) rexmode|=FXRex::Capture;                           // Capturing parentheses
  if(flgs&SEARCH_IGNORECASE) rexmode|=FXRex::IgnoreCase;        // Case insensitivity
  if(!(flgs&SEARCH_REGEX)) rexmode|=FXRex::Verbatim;            // Verbatim match

  // Try parse the regex
  if(rex.parse(string,rexmode)==FXRex::ErrOK){

    // Make all characters contiguous in the buffer
    squeezegap();

    // Search forward
    if(flgs&SEARCH_FORWARD){
      if(start<=length){
        if(rex.search(buffer,length,FXMAX(start,0),length,FXRex::Normal,beg,end,npar)>=0) return true;
        }
      if((flgs&SEARCH_WRAP) && (start>0)){
        if(rex.search(buffer,length,0,FXMIN(start,length),FXRex::Normal,beg,end,npar)>=0) return true;
        }
      return false;
      }

    // Search backward
    if(flgs&SEARCH_BACKWARD){
      if(0<=start){
        if(rex.search(buffer,length,FXMIN(start,length),0,FXRex::Normal,beg,end,npar)>=0) return true;
        }
      if((flgs&SEARCH_WRAP) && (start<length)){
        if(rex.search(buffer,length,length,FXMAX(start,0),FXRex::Normal,beg,end,npar)>=0) return true;
        }
      return false;
      }

    // Anchored match
    return rex.amatch(buffer,length,start,FXRex::Normal,beg,end,npar);
    }
  return false;
  }

/*******************************************************************************/

// Find line number from visible pos
FXint FXText::posToLine(FXint pos,FXint ln) const {
  FXASSERT(0<=ln && ln<nvisrows);
  FXASSERT(visrows[ln]<=pos && pos<=visrows[nvisrows]);
  while(ln<nvisrows-1 && visrows[ln+1]<=pos && visrows[ln]<visrows[ln+1]) ln++;
  FXASSERT(0<=ln && ln<nvisrows);
  FXASSERT(visrows[ln]<=pos && pos<=visrows[ln+1]);
  return ln;
  }


// Return text position containing x, y coordinate
FXint FXText::getPosContaining(FXint x,FXint y) const {
  register FXint row,ls,le,cx,cw,ch;
  y=y-pos_y-margintop-getVisibleY();
  row=y/font->getFontHeight();
  if(row<0) return 0;               // Before first row
  if(row>=nrows) return length;     // Below last row
  if(row<toprow){                   // Above visible area
    ls=prevRow(toppos,toprow-row);
    le=nextRow(ls,1);
    }
  else if(row>=toprow+nvisrows){    // Below visible area
    ls=nextRow(toppos,row-toprow);
    le=nextRow(ls,1);
    }
  else{                             // Inside visible area
    ls=visrows[row-toprow];
    le=visrows[row-toprow+1];
    }
  x=x-pos_x-marginleft-getVisibleX();
  if(x<0) return ls;                // Before begin of line
  FXASSERT(0<=ls);
  FXASSERT(ls<=le);
  FXASSERT(le<=length);
  cx=0;
  while(ls<le){                     // Find character containing x position
    ch=getChar(ls);
    if(ls==le-1 && Unicode::isSpace(ch)) return ls;     // Last character is newline or blank (due to wrapping)
    cw=charWidth(ch,cx);
    if(x<cx+cw) return ls;
    cx+=cw;
    ls+=getCharLen(ls);
    }
  return le;
  }


// Localize position at x,y
FXint FXText::getPosAt(FXint x,FXint y) const {
  register FXint row,ls,le,cx,cw,ch;
  y=y-pos_y-margintop-getVisibleY();
  row=y/font->getFontHeight();
  if(row<0) return 0;               // Before first row
  if(row>=nrows) return length;     // Below last row
  if(row<toprow){                   // Above visible area
    ls=prevRow(toppos,toprow-row);
    le=nextRow(ls,1);
    }
  else if(row>=toprow+nvisrows){    // Below visible area
    ls=nextRow(toppos,row-toprow);
    le=nextRow(ls,1);
    }
  else{                             // Inside visible area
    ls=visrows[row-toprow];
    le=visrows[row-toprow+1];
    }
  x=x-pos_x-marginleft-getVisibleX();
  if(x<0) return ls;                // Before begin of line
  FXASSERT(0<=ls);
  FXASSERT(ls<=le);
  FXASSERT(le<=length);
  if(ls<le && (((ch=getByte(le-1))=='\n') || (le<length && Ascii::isSpace(ch)))) le--;
  cx=0;
  while(ls<le){
    ch=getChar(ls);
    cw=charWidth(ch,cx);
    if(x<=(cx+(cw>>1))) return ls;
    cx+=cw;
    ls+=getCharLen(ls);
    }
  return le;
  }


// Determine Y from position pos
FXint FXText::getYOfPos(FXint pos) const {
  register FXint h=font->getFontHeight();
  register FXint n,y;

  // Inside text
  pos=FXCLAMP(0,pos,length);

  // Above visible part of buffer
  if(pos<visrows[0]){
    n=countRows(rowStart(pos),visrows[0]);
    y=(toprow-n)*h;
    FXTRACE((150,"getYOfPos(%d < visrows[0]=%d) = %d\n",pos,visrows[0],margintop+y));
    }

  // In visible part of buffer
  else if(pos<visrows[nvisrows]){
    n=posToLine(pos,0);
    y=(toprow+n)*h;
    FXTRACE((150,"getYOfPos(visrows[0]=%d <= %d <= visrows[%d]=%d) = %d\n",visrows[0],pos,nvisrows,visrows[nvisrows],margintop+y));
    }

  // Below visible part of buffer
  else{
    n=countRows(visrows[0],pos);
    y=(toprow+n)*h;
    FXTRACE((150,"getYOfPos(%d > visrows[%d]=%d) = %d\n",pos,nvisrows,visrows[nvisrows],margintop+y));
    }
  return getVisibleY()+margintop+y;
  }


// Calculate X position of pos
FXint FXText::getXOfPos(FXint pos) const {
  register FXint base=rowStart(pos);
  return getVisibleX()+marginleft+lineWidth(base,pos-base);
  }


/*******************************************************************************/

// Return true if position is fully visible
FXbool FXText::isPosVisible(FXint pos) const {
  if(visrows[0]<=pos && pos<=visrows[nvisrows]){
    register FXint h=font->getFontHeight();
    register FXint y=pos_y+margintop+(toprow+posToLine(pos,0))*h;
    return margintop<=y && y+h<=getVisibleHeight()-marginbottom;
    }
  return false;
  }


// Force position to become fully visible
void FXText::makePositionVisible(FXint pos){
  register FXint vx=getVisibleX();
  register FXint vy=getVisibleY();
  register FXint vw=getVisibleWidth();
  register FXint vh=getVisibleHeight();
  register FXint p=validPos(pos);
  register FXint x=getXOfPos(p);
  register FXint y=getYOfPos(p);
  register FXint ny=pos_y;
  register FXint nx=pos_x;

  // Check vertical visibility
  if(pos_y+y<vy+margintop){
    ny=vy+margintop-y;
    nx=0;
    }
  else if(pos_y+y+font->getFontHeight()>vy+vh-marginbottom){
    ny=vy+vh-marginbottom-y-font->getFontHeight();
    nx=0;
    }

  // Check horizontal visibility
  if(pos_x+x<vx+marginleft){
    nx=vx+marginleft-x;
    }
  else if(pos_x+x>vx+vw-marginright){
    nx=vx+vw-marginright-x;
    }

  // If needed, scroll
  if(nx!=pos_x || ny!=pos_y){
    setPosition(nx,ny);
    }
  }


// Make line containing pos the top visible line
void FXText::setTopLine(FXint pos){
  setPosition(pos_x,getVisibleY()+margintop-getYOfPos(pos));
  }


// Make line containing pos the bottom visible line
void FXText::setBottomLine(FXint pos){
  setPosition(pos_x,getVisibleY()+getVisibleHeight()-marginbottom-getYOfPos(pos)-font->getFontHeight());
  }


// Center line of pos in the middle of the screen
void FXText::setCenterLine(FXint pos){
  setPosition(pos_x,getVisibleY()+getVisibleHeight()/2+font->getFontHeight()/2-getYOfPos(pos));
  }


// Get top line
FXint FXText::getTopLine() const {
  return visrows[0];
  }


// Get bottom line
FXint FXText::getBottomLine() const {
  return visrows[nvisrows-1];
  }


// Move content
void FXText::moveContents(FXint x,FXint y){
  register FXint delta=-y/font->getFontHeight()-toprow;
  register FXint vx=getVisibleX();
  register FXint vy=getVisibleY();
  register FXint vw=getVisibleWidth();
  register FXint vh=getVisibleHeight();
  register FXint dx=x-pos_x;
  register FXint dy=y-pos_y;
  register FXint i;

  // Erase fragments of cursor overhanging margins
  eraseCursorOverhang();

  // Scrolled up one or more lines
  if(delta<0){
    if(toprow+delta<=0){
      toppos=0;
      toprow=0;
      }
    else{
      toppos=prevRow(toppos,-delta);
      toprow=toprow+delta;
      }
    if(-delta<nvisrows){
      for(i=nvisrows; i>=-delta; i--) visrows[i]=visrows[delta+i];
      calcVisRows(0,-delta);
      }
    else{
      calcVisRows(0,nvisrows);
      }
    }

  // Scrolled down one or more lines
  else if(delta>0){
    if(toprow+delta>=nrows-1){
      toppos=rowStart(length);
      toprow=nrows-1;
      }
    else{
      toppos=nextRow(toppos,delta);
      toprow=toprow+delta;
      }
    if(delta<nvisrows){
      for(i=0; i<=nvisrows-delta; i++) visrows[i]=visrows[delta+i];
      calcVisRows(nvisrows-delta,nvisrows);
      }
    else{
      calcVisRows(0,nvisrows);
      }
    }

  // This is now the new keep position
  keeppos=toppos;

  // Hopefully, all is still in range
  FXASSERT(0<=toprow && toprow<nrows);
  FXASSERT(0<=toppos && toppos<=length);

  // Scroll stuff in the bar only vertically
  scroll(vx-barwidth,vy,barwidth,vh,0,dy);

  // Scroll the text
  scroll(vx+marginleft,vy+margintop,vw-marginleft-marginright,vh-margintop-marginbottom,dx,dy);

  pos_x=x;
  pos_y=y;
  }

/*******************************************************************************/

// Recalculate line starts
void FXText::calcVisRows(FXint startline,FXint endline){
  register FXint pos;
  FXASSERT(nvisrows>0);
  startline=FXCLAMP(0,startline,nvisrows);
  endline=FXCLAMP(0,endline,nvisrows);
  if(startline<=endline){
    if(startline==0){
      FXASSERT(0<=toppos && toppos<=length);
      visrows[0]=toppos;
      startline=1;
      }
    pos=visrows[startline-1];
    if(options&TEXT_WORDWRAP){
      while(startline<=endline && pos<length){
        pos=wrap(pos);
        FXASSERT(0<=pos && pos<=length);
        visrows[startline++]=pos;
        }
      }
    else{
      while(startline<=endline && pos<length){
        pos=nextLine(pos);
        FXASSERT(0<=pos && pos<=length);
        visrows[startline++]=pos;
        }
      }
    while(startline<=endline){
      visrows[startline++]=length;
      }
    }
  }


// Completely reflow the text, because font, wrapwidth, or all of the
// text may have changed and everything needs to be recomputed
void FXText::recompute(){
  FXint ww1,ww2,ww3,hh1,hh2,hh3,hh;

  // Make it point somewhere sensible
  keeppos=FXCLAMP(0,keeppos,length);

  // Make sure we're pointing to the start of a row again
  toppos=rowStart(keeppos);

  // Font height
  hh=font->getFontHeight();

  // Get start
  cursorstartpos=rowStart(cursorpos);
  cursorendpos=nextRow(cursorstartpos);
  cursorcol=indentFromPos(cursorstartpos,cursorpos);

  // Avoid measuring huge chunks of text twice!
  if(cursorstartpos<toppos){
    cursorrow=measureText(0,cursorstartpos,ww1,hh1);
    toprow=cursorrow+measureText(cursorstartpos,toppos,ww2,hh2);
    nrows=toprow+measureText(toppos,length+1,ww3,hh3);
    }
  else{
    toprow=measureText(0,toppos,ww1,hh1);
    cursorrow=toprow+measureText(toppos,cursorstartpos,ww2,hh2);
    nrows=cursorrow+measureText(cursorstartpos,length+1,ww3,hh3);
    }

  textWidth=FXMAX3(ww1,ww2,ww3);
  textHeight=hh1+hh2+hh3;

  // Adjust position, keeping same fractional position
  pos_y=-toprow*hh-(-pos_y%hh);

  // Number of visible lines has changed
  nvisrows=(height-margintop-marginbottom+hh+hh-1)/hh;
  if(nvisrows<1) nvisrows=1;

  // Resize line start array
  resizeElms(visrows,nvisrows+1);

  // Recompute line starts
  calcVisRows(0,nvisrows);

  FXTRACE((150,"recompute : toprow=%d toppos=%d nrows=%d nvisrows=%d textWidth=%d textHeight=%d length=%d cursorrow=%d cursorcol=%d\n",toprow,toppos,nrows,nvisrows,textWidth,textHeight,length,cursorrow,cursorcol));

  // Done with that
  flags&=~FLAG_RECALC;
  }

/*******************************************************************************/

// Return visible scroll-area x position
FXint FXText::getVisibleX() const {
  return barwidth;
  }


// Return visible scroll-area y position
FXint FXText::getVisibleY() const {
  return 0;
  }


// Return visible scroll-area width
FXint FXText::getVisibleWidth() const {
  return width-vertical->getWidth()-barwidth;
  }


// Return visible scroll-area height
FXint FXText::getVisibleHeight() const {
  return height-horizontal->getHeight();
  }


// Determine content width of scroll area
FXint FXText::getContentWidth(){
  if(flags&FLAG_RECALC) recompute();
  return marginleft+marginright+textWidth;
  }


// Determine content height of scroll area
FXint FXText::getContentHeight(){
  if(flags&FLAG_RECALC) recompute();
  return margintop+marginbottom+textHeight;
  }


// Recalculate layout
void FXText::layout(){
  FXint fh=font->getFontHeight();
  FXint fw=font->getFontWidth();
  FXint ovv=nvisrows;
  FXint oww=wrapwidth;

  // Compute new wrap width; needed to reflow text
  if(options&TEXT_FIXEDWRAP){
    wrapwidth=wrapcolumns*font->getTextWidth("x",1);
    }
  else{
    wrapwidth=width-barwidth-marginleft-marginright;
    if(!(options&VSCROLLER_NEVER)) wrapwidth-=vertical->getDefaultWidth();
    }

  // Wrap width changed, so reflow; when using fixed pitch font,
  // we only reflow if the number of columns has changed.
  if((options&TEXT_WORDWRAP) && (wrapwidth!=oww)){
    if(!font->isFontMono() || (wrapwidth/fw!=oww/fw)) flags|=FLAG_RECALC;
    }

  // Scrollbars adjusted
  placeScrollBars(width-barwidth,height);

  // Number of visible lines may have changed
  nvisrows=(height-margintop-marginbottom+fh+fh-1)/fh;
  if(nvisrows<1) nvisrows=1;

  // Number of visible lines changed
  if(nvisrows!=ovv){

    // Resize line start array
    resizeElms(visrows,nvisrows+1);

    // Recompute line starts
    calcVisRows(0,nvisrows);
    }

  // Set line size based on font
  vertical->setLine(fh);
  horizontal->setLine(fw);

  // Force repaint
  update();

  // Done
  flags&=~FLAG_DIRTY;
  }


/*******************************************************************************/

// Move the cursor
void FXText::setCursorPos(FXint pos,FXbool notify){
  FXint p=validPos(pos);
  if(cursorpos!=p){
    if(isEditable()) drawCursor(0);
    if(p<cursorstartpos || cursorendpos<=p){    // Move to other line?
      FXint cursorstartold=cursorstartpos;
      FXint cursorendold=cursorendpos;
      cursorstartpos=rowStart(p);
      cursorendpos=nextRow(cursorstartpos);
      if(cursorstartpos<cursorstartold){
        cursorrow=cursorrow-countRows(cursorstartpos,cursorstartold);
        }
      else{
        cursorrow=cursorrow+countRows(cursorstartold,cursorstartpos);
        }
      if(options&TEXT_SHOWACTIVE){
        updateRange(cursorstartold,cursorendold);
        updateRange(cursorstartpos,cursorendpos);
        }
      }
    cursorcol=indentFromPos(cursorstartpos,p);
    cursorpos=p;
    prefcol=-1;
    if(isEditable()) drawCursor(FLAG_CARET);
    if(target && notify){
      target->tryHandle(this,FXSEL(SEL_CHANGED,message),(void*)(FXival)cursorpos);
      }
    }
  }


// Set cursor row
void FXText::setCursorRow(FXint row,FXbool notify){
  register FXint col,newrow,newpos;
  if(row!=cursorrow){
    if(row<0) row=0;
    if(row>=nrows) row=nrows-1;
    col=(0<=prefcol) ? prefcol : cursorcol;
    if(row>cursorrow){
      newrow=nextRow(cursorpos,row-cursorrow);
      }
    else{
      newrow=prevRow(cursorpos,cursorrow-row);
      }
    newpos=posFromIndent(newrow,col);
    moveCursor(newpos,notify);
    prefcol=col;
    }
  }


// Set cursor column
void FXText::setCursorColumn(FXint col,FXbool notify){
  register FXint newpos;
  if(cursorcol!=col){
    newpos=posFromIndent(cursorstartpos,col);
    moveCursor(newpos,notify);
    }
  }


// Move cursor
void FXText::moveCursor(FXint pos,FXbool notify){
  setCursorPos(pos,notify);
  makePositionVisible(cursorpos);
  setAnchorPos(cursorpos);
  killSelection(notify);
  flashMatching();
  }


// Move cursor and select
void FXText::moveCursorAndSelect(FXint pos,FXuint select,FXbool notify){
  setCursorPos(pos,notify);
  makePositionVisible(cursorpos);
  extendSelection(cursorpos,select,notify);
  }


// Set anchor position
void FXText::setAnchorPos(FXint pos){
  anchorpos=validPos(pos);
  }

/*******************************************************************************/

// There has been a mutation in the buffer
void FXText::mutation(FXint pos,FXint ncins,FXint ncdel,FXint nrins,FXint nrdel){
  register FXint ncdelta=ncins-ncdel;
  register FXint nrdelta=nrins-nrdel;
  register FXint line,i,x,y;

  FXTRACE((150,"BEFORE: pos=%d ncins=%d ncdel=%d nrins=%d nrdel=%d toppos=%d toprow=%d nrows=%d nvisrows=%d\n",pos,ncins,ncdel,nrins,nrdel,toppos,toprow,nrows,nvisrows));

  // All of the change is below the last visible line
  if(visrows[nvisrows]<pos){
    FXTRACE((150,"change below visible\n"));
    nrows+=nrdelta;
    }

  // All change above first visible line
  else if(pos+ncdel<=visrows[0]){
    FXTRACE((150,"change above visible\n"));
    nrows+=nrdelta;
    toprow+=nrdelta;
    toppos+=ncdelta;
    keeppos=toppos;
    for(i=0; i<=nvisrows; i++) visrows[i]+=ncdelta;
    pos_y-=nrdelta*font->getFontHeight();
    FXASSERT(0<=toppos && toppos<=length);
    if(nrdelta) update(0,0,barwidth,height);
    }

  // Top visible part unchanged
  else if(visrows[0]<=pos){
    line=posToLine(pos,0);
    FXTRACE((150,"change below visible line %d\n",line));

    // More lines means paint the bottom half
    if(nrdelta>0){
      FXTRACE((150,"inserted %d rows\n",nrdelta));
      nrows+=nrdelta;
      for(i=nvisrows; i>line+nrdelta; i--) visrows[i]=visrows[i-nrdelta]+ncdelta;
      calcVisRows(line+1,line+nrins);
      FXASSERT(0<=toppos && toppos<=length);
      y=pos_y+margintop+(toprow+line)*font->getFontHeight();
      update(barwidth,y,width-barwidth,height-y);
      }

    // Less lines means paint bottom half also
    else if(nrdelta<0){
      FXTRACE((150,"deleted %d rows\n",-nrdelta));
      nrows+=nrdelta;
      for(i=line+1; i<=nvisrows+nrdelta; i++) visrows[i]=visrows[i-nrdelta]+ncdelta;
      calcVisRows(nvisrows+nrdelta,nvisrows);
      calcVisRows(line+1,line+nrins);
      FXASSERT(0<=toppos && toppos<=length);
      y=pos_y+margintop+(toprow+line)*font->getFontHeight();
      update(barwidth,y,width-barwidth,height-y);
      }

    // Same lines means paint the changed area only
    else{
      FXTRACE((150,"same number of rows\n"));
      for(i=line+1; i<=nvisrows; i++) visrows[i]=visrows[i]+ncdelta;
      calcVisRows(line+1,line+nrins);
      FXASSERT(0<=toppos && toppos<=length);
      if(nrins==0){
        x=pos_x+marginleft+barwidth+lineWidth(visrows[line],pos-visrows[line]);
        y=pos_y+margintop+(toprow+line)*font->getFontHeight();
        update(x,y,width-x,font->getFontHeight());
        FXTRACE((150,"update(%d,%d,%d,%d)\n",x,y,width-x,font->getFontHeight()));
        }
      else{
        y=pos_y+margintop+(toprow+line)*font->getFontHeight();
        update(barwidth,y,width-barwidth,nrins*font->getFontHeight());
        FXTRACE((150,"update(%d,%d,%d,%d)\n",0,y,width,nrins*font->getFontHeight()));
        }
      }
    }

  // Bottom visible part unchanged
  else if(pos+ncdel<visrows[nvisrows-1]){
    nrows+=nrdelta;
    line=1+posToLine(pos+ncdel,0);
    FXASSERT(0<=line && line<nvisrows);
    FXASSERT(pos+ncdel<=visrows[line]);
    FXTRACE((150,"change above visible line %d\n",line));

    // Too few lines left to display
    if(toprow+nrdelta<=line){
      FXTRACE((150,"reset to top\n"));
      toprow=0;
      toppos=0;
      keeppos=0;
      pos_y=0;
      calcVisRows(0,nvisrows);
      FXASSERT(0<=toppos && toppos<=length);
      update();
      }

    // Redisplay only the top
    else{
      FXTRACE((150,"redraw top %d lines\n",line));
      toprow+=nrdelta;
      toppos=prevRow(visrows[line]+ncdelta,line);
      keeppos=toppos;
      pos_y-=nrdelta*font->getFontHeight();
      calcVisRows(0,nvisrows);
      FXASSERT(0<=toppos && toppos<=length);
      update(barwidth,0,width-barwidth,pos_y+margintop+(toprow+line)*font->getFontHeight());
      if(nrdelta) update(0,0,barwidth,height);
      }
    }

  // All visible text changed
  else{
    FXTRACE((150,"change all visible lines\n"));
    nrows+=nrdelta;

    // Reset to top because too few lines left
    if(toprow>=nrows){
      FXTRACE((150,"reset to top\n"));
      toprow=0;
      toppos=0;
      keeppos=0;
      FXASSERT(0<=toppos && toppos<=length);
      pos_y=0;
      }

    // Maintain same row as before
    else{
      FXTRACE((150,"set to same row %d\n",toprow));
      toppos=nextRow(0,toprow);
      keeppos=toppos;
      FXASSERT(0<=toppos && toppos<=length);
      }
    calcVisRows(0,nvisrows);
    update();
    }

  FXTRACE((150,"AFTER : pos=%d ncins=%d ncdel=%d nrins=%d nrdel=%d toppos=%d toprow=%d nrows=%d\n",pos,ncins,ncdel,nrins,nrdel,toppos,toprow,nrows));
  }



// Replace m characters at pos by n characters
void FXText::replace(FXint pos,FXint m,const FXchar *text,FXint n,FXint style){
  FXint nrdel,nrins,ncdel,ncins,wbeg,wend,del,wdel,hdel,wins,hins;

  FXTRACE((150,"pos=%d mdel=%d nins=%d\n",pos,m,n));

  // Delta in characters
  del=n-m;

  // Bracket potentially affected character range for wrapping purposes
  wbeg=changeBeg(pos);
  wend=changeEnd(pos+m);

  // Measure stuff prior to change
  nrdel=measureText(wbeg,wend,wdel,hdel);
  ncdel=wend-wbeg;

  FXTRACE((150,"wbeg=%d wend=%d nrdel=%d ncdel=%d length=%d wdel=%d hdel=%d\n",wbeg,wend,nrdel,ncdel,length,wdel,hdel));

  // Modify the buffer
  sizegap(del);
  movegap(pos);
  memcpy(&buffer[pos],text,n);
  if(sbuffer){memset(&sbuffer[pos],style,n);}
  gapstart+=n;
  gapend+=m;
  length+=del;

  // Measure stuff after change
  nrins=measureText(wbeg,wend+n-m,wins,hins);
  ncins=wend+n-m-wbeg;

  FXTRACE((150,"wbeg=%d wend+n-m=%d nrins=%d ncins=%d length=%d wins=%d hins=%d\n",wbeg,wend+n-m,nrins,ncins,length,wins,hins));

  // Update stuff
  mutation(wbeg,ncins,ncdel,nrins,nrdel);

  // Fix text metrics
  textHeight=textHeight+hins-hdel;
  textWidth=FXMAX(textWidth,wins);

  // Fix selection range
  FXASSERT(selstartpos<=selendpos);
  if(pos+m<=selstartpos){                               // Selection above change
    selstartpos+=del;
    selendpos+=del;
    }
  else if(pos<selendpos){                               // Selection overlaps change
    if(pos<=selstartpos) selstartpos=pos;
    if(selendpos<=pos+m) selendpos=pos+n; else selendpos+=del;
    }

  // Fix highlight range
  FXASSERT(hilitestartpos<=hiliteendpos);
  if(pos+m<=hilitestartpos){                            // Highlight above change
    hilitestartpos+=del;
    hiliteendpos+=del;
    }
  else if(pos<hiliteendpos){                            // Highlight overlaps change
    if(pos<=hilitestartpos) hilitestartpos=pos;
    if(hiliteendpos<=pos+m) hiliteendpos=pos+n; else hiliteendpos+=del;
    }

  // Fix anchor position
  if(pos+m<=anchorpos)
    anchorpos+=del;
  else if(pos<=anchorpos)
    anchorpos=pos+n;

  // Cursor is beyond changed area, so simple update
  if(wend<=cursorpos){
    cursorpos+=del;
    cursorstartpos+=del;
    cursorendpos+=del;
    cursorrow+=nrins-nrdel;
    }

  // Cursor inside changed area, recompute cursor data
  else if(wbeg<=cursorpos){
    if(pos+m<=cursorpos) cursorpos+=del;                // Beyond changed text
    else if(pos<=cursorpos) cursorpos=pos+n;            // Inside changed text
    cursorstartpos=rowStart(cursorpos);
    cursorendpos=nextRow(cursorstartpos);
    cursorcol=indentFromPos(cursorstartpos,cursorpos);
    if(cursorstartpos<toppos){
      cursorrow=toprow-countRows(cursorstartpos,toppos);
      }
    else{
      cursorrow=toprow+countRows(toppos,cursorstartpos);
      }
    }

  // Reconcile scrollbars
  placeScrollBars(width-barwidth,height);

  // Forget preferred column
  prefcol=-1;

  // Text was changed
  modified=true;
  }


/*******************************************************************************/

// Change the text in the buffer to new text
void FXText::setText(const FXchar* text,FXint n,FXbool notify){
  setStyledText(text,n,0,notify);
  }


// Change all of the text
void FXText::setText(const FXString& text,FXbool notify){
  setStyledText(text,0,notify);
  }


// Change the text in the buffer to new text
void FXText::setStyledText(const FXchar* text,FXint n,FXint style,FXbool notify){
  FXTextChange textchange;
  if(n<0){ fxerror("%s::setStyledText: bad argument.\n",getClassName()); }
  if(!resizeElms(buffer,n+MINSIZE)){
    fxerror("%s::setStyledText: out of memory.\n",getClassName());
    }
  memcpy(buffer,text,n);
  if(sbuffer){
    if(!resizeElms(sbuffer,n+MINSIZE)){
      fxerror("%s::setStyledText: out of memory.\n",getClassName());
      }
    memset(sbuffer,style,n);
    }
  gapstart=n;
  gapend=gapstart+MINSIZE;
  length=n;
  toppos=0;
  toprow=0;
  keeppos=0;
  selstartpos=0;
  selendpos=0;
  hilitestartpos=0;
  hiliteendpos=0;
  anchorpos=0;
  cursorpos=0;
  cursorstartpos=0;
  cursorendpos=0;
  cursorrow=0;
  cursorcol=0;
  prefcol=-1;
  pos_x=0;
  pos_y=0;
  modified=false;
  textchange.pos=0;
  textchange.ndel=0;
  textchange.nins=n;
  textchange.ins=(FXchar*)text;
  textchange.del=(FXchar*)"";
  if(notify && target){
    target->tryHandle(this,FXSEL(SEL_INSERTED,message),(void*)&textchange);
    target->tryHandle(this,FXSEL(SEL_CHANGED,message),(void*)(FXival)cursorpos);
    }
  recalc();
  layout();
  update();
  }


// Change all of the text
void FXText::setStyledText(const FXString& text,FXint style,FXbool notify){
  setStyledText(text.text(),text.length(),style,notify);
  }


// Replace text by other text
void FXText::replaceText(FXint pos,FXint m,const FXchar *text,FXint n,FXbool notify){
  replaceStyledText(pos,m,text,n,0,notify);
  }


// Replace text by other text
void FXText::replaceText(FXint pos,FXint m,const FXString& text,FXbool notify){
  replaceStyledText(pos,m,text,0,notify);
  }


// Replace m characters at pos by n characters
void FXText::replaceStyledText(FXint pos,FXint m,const FXchar *text,FXint n,FXint style,FXbool notify){
  FXTextChange textchange;
  if(n<0 || m<0 || pos<0 || length<pos+m){ fxerror("%s::replaceStyledText: bad argument.\n",getClassName()); }
  FXTRACE((130,"replaceStyledText(%d,%d,text,%d)\n",pos,m,n));
  textchange.pos=pos;
  textchange.ndel=m;
  textchange.nins=n;
  textchange.ins=(FXchar*)text;
  allocElms(textchange.del,m);
  extractText(textchange.del,pos,m);
  replace(pos,m,text,n,style);
  if(notify && target){
    target->tryHandle(this,FXSEL(SEL_REPLACED,message),(void*)&textchange);
    target->tryHandle(this,FXSEL(SEL_CHANGED,message),(void*)(FXival)cursorpos);
    }
  freeElms(textchange.del);
  }


// Replace m characters at pos by n characters
void FXText::replaceStyledText(FXint pos,FXint m,const FXString& text,FXint style,FXbool notify){
  replaceStyledText(pos,m,text.text(),text.length(),style,notify);
  }


// Add text at the end
void FXText::appendText(const FXchar *text,FXint n,FXbool notify){
  appendStyledText(text,n,0,notify);
  }


// Add text at the end
void FXText::appendText(const FXString& text,FXbool notify){
  appendStyledText(text,0,notify);
  }


// Add text at the end
void FXText::appendStyledText(const FXchar *text,FXint n,FXint style,FXbool notify){
  FXTextChange textchange;
  if(n<0){ fxerror("%s::appendStyledText: bad argument.\n",getClassName()); }
  FXTRACE((130,"appendStyledText(text,%d)\n",n));
  textchange.pos=length;
  textchange.ndel=0;
  textchange.nins=n;
  textchange.ins=(FXchar*)text;
  textchange.del=(FXchar*)"";
  replace(length,0,text,n,style);
  if(notify && target){
    target->tryHandle(this,FXSEL(SEL_INSERTED,message),(void*)&textchange);
    target->tryHandle(this,FXSEL(SEL_CHANGED,message),(void*)(FXival)cursorpos);
    }
  }


// Add text at the end
void FXText::appendStyledText(const FXString& text,FXint style,FXbool notify){
  appendStyledText(text.text(),text.length(),style,notify);
  }


// Insert some text at pos
void FXText::insertText(FXint pos,const FXchar *text,FXint n,FXbool notify){
  insertStyledText(pos,text,n,0,notify);
  }


// Insert some text at pos
void FXText::insertText(FXint pos,const FXString& text,FXbool notify){
  insertStyledText(pos,text,0,notify);
  }


// Insert some text at pos
void FXText::insertStyledText(FXint pos,const FXchar *text,FXint n,FXint style,FXbool notify){
  FXTextChange textchange;
  if(n<0 || pos<0 || length<pos){ fxerror("%s::insertStyledText: bad argument.\n",getClassName()); }
  FXTRACE((130,"insertStyledText(%d,text,%d)\n",pos,n));
  textchange.pos=pos;
  textchange.ndel=0;
  textchange.nins=n;
  textchange.ins=(FXchar*)text;
  textchange.del=(FXchar*)"";
  replace(pos,0,text,n,style);
  if(notify && target){
    target->tryHandle(this,FXSEL(SEL_INSERTED,message),(void*)&textchange);
    target->tryHandle(this,FXSEL(SEL_CHANGED,message),(void*)(FXival)cursorpos);
    }
  }


// Insert some text at pos
void FXText::insertStyledText(FXint pos,const FXString& text,FXint style,FXbool notify){
  insertStyledText(pos,text.text(),text.length(),style,notify);
  }


// Remove some text at pos
void FXText::removeText(FXint pos,FXint n,FXbool notify){
  FXTextChange textchange;
  if(n<0 || pos<0 || length<pos+n){ fxerror("%s::removeText: bad argument.\n",getClassName()); }
  FXTRACE((130,"removeText(%d,%d)\n",pos,n));
  textchange.pos=pos;
  textchange.ndel=n;
  textchange.nins=0;
  textchange.ins=(FXchar*)"";
  allocElms(textchange.del,n);
  extractText(textchange.del,pos,n);
  replace(pos,n,NULL,0,0);
  if(notify && target){
    target->tryHandle(this,FXSEL(SEL_DELETED,message),(void*)&textchange);
    target->tryHandle(this,FXSEL(SEL_CHANGED,message),(void*)(FXival)cursorpos);
    }
  freeElms(textchange.del);
  }


// Remove all text from the buffer
void FXText::clearText(FXbool notify){
  removeText(0,length,notify);
  }


// Change style of text range
void FXText::changeStyle(FXint pos,FXint n,FXint style){
  if(n<0 || pos<0 || length<pos+n){ fxerror("%s::changeStyle: bad argument.\n",getClassName()); }
  if(sbuffer){
    if(pos+n<=gapstart){
      memset(sbuffer+pos,style,n);
      }
    else if(gapstart<=pos){
      memset(sbuffer+pos-gapstart+gapend,style,n);
      }
    else{
      memset(sbuffer+pos,style,gapstart-pos);
      memset(sbuffer+gapend,style,pos+n-gapstart);
      }
    updateRange(pos,pos+n);
    }
  }


// Change style of text range from style-array
void FXText::changeStyle(FXint pos,const FXchar* style,FXint n){
  if(n<0 || pos<0 || length<pos+n){ fxerror("%s::changeStyle: bad argument.\n",getClassName()); }
  if(sbuffer && style){
    if(pos+n<=gapstart){
      memcpy(sbuffer+pos,style,n);
      }
    else if(gapstart<=pos){
      memcpy(sbuffer+gapend-gapstart+pos,style,n);
      }
    else{
      memcpy(sbuffer+pos,style,gapstart-pos);
      memcpy(sbuffer+gapend,style+gapstart-pos,pos+n-gapstart);
      }
    updateRange(pos,pos+n);
    }
  }


// Change style of text range from style-array
void FXText::changeStyle(FXint pos,const FXString& style){
  changeStyle(pos,style.text(),style.length());
  }


// Grab range of text
void FXText::extractText(FXchar *text,FXint pos,FXint n) const {
  if(n<0 || pos<0 || length<pos+n){ fxerror("%s::extractText: bad argument.\n",getClassName()); }
  FXASSERT(0<=n && 0<=pos && pos+n<=length);
  if(pos+n<=gapstart){
    memcpy(text,buffer+pos,n);
    }
  else if(gapstart<=pos){
    memcpy(text,buffer+gapend-gapstart+pos,n);
    }
  else{
    memcpy(text,buffer+pos,gapstart-pos);
    memcpy(text+gapstart-pos,buffer+gapend,pos+n-gapstart);
    }
  }


// Grab range of text
void FXText::extractText(FXString& text,FXint pos,FXint n) const {
  text.length(n);
  extractText(text.text(),pos,n);
  }


// Grab range of style
void FXText::extractStyle(FXchar *style,FXint pos,FXint n) const {
  if(n<0 || pos<0 || length<pos+n){ fxerror("%s::extractStyle: bad argument.\n",getClassName()); }
  FXASSERT(0<=n && 0<=pos && pos+n<=length);
  if(sbuffer){
    if(pos+n<=gapstart){
      memcpy(style,sbuffer+pos,n);
      }
    else if(gapstart<=pos){
      memcpy(style,sbuffer+gapend-gapstart+pos,n);
      }
    else{
      memcpy(style,sbuffer+pos,gapstart-pos);
      memcpy(style+gapstart-pos,sbuffer+gapend,pos+n-gapstart);
      }
    }
  }


// Grab range of style
void FXText::extractStyle(FXString& style,FXint pos,FXint n) const {
  style.length(n);
  extractStyle(style.text(),pos,n);
  }


// Retrieve text into buffer
void FXText::getText(FXchar* text,FXint n) const {
  extractText(text,0,n);
  }


// Retrieve text into buffer
void FXText::getText(FXString& text) const {
  extractText(text,0,getLength());
  }


// We return a constant copy of the buffer
FXString FXText::getText() const {
  FXString value;
  extractText(value,0,getLength());
  return value;
  }


// Get selected text
FXString FXText::getSelectedText() const {
  FXString value;
  extractText(value,selstartpos,selendpos-selstartpos);
  return value;
  }

/*******************************************************************************/

// End of overstruck character range
FXint FXText::overstruck(FXint start,FXint end,const FXchar *text,FXint n){
  if(!memchr(text,'\n',n)){
    FXint sindent,nindent,oindent,p,c;
    const FXchar *ptr;

    // Measure indent at pos
    for(p=lineStart(start),sindent=0; p<start; p+=getCharLen(p)){
      sindent+=(getChar(p)=='\t') ? (tabcolumns-sindent%tabcolumns) : 1;
      }

    // Measure indent at end of (first line of the) new text
    for(ptr=text,nindent=sindent; ptr<text+n; ptr=wcinc(ptr)){
      nindent+=(wc(ptr)=='\t') ? (tabcolumns-nindent%tabcolumns) : 1;
      }

    // Now figure out how much text to replace
    for(p=start,oindent=sindent; p<length; p+=getCharLen(p)){
      c=getChar(p);
      if(c=='\n') break;                // Stuff past the newline just gets inserted
      oindent+=(c=='\t') ? (tabcolumns-oindent%tabcolumns) : 1;
      if(oindent>=nindent){              // Replace string fits inside here
        if(oindent==nindent) p+=getCharLen(p);
        break;
        }
      }
    end=p;
    }
  return end;
  }

/*
// Insert text at cursor
void FXText::enterText(const FXchar *text,FXint n,FXbool repsel,FXbool notify){
  FXint start=cursorpos;
  FXint end=cursorpos;

  // Replace selected characters
  if(isPosSelected(cursorpos) && repsel){
    start=selstartpos;
    end=selendpos;
    }

  // Replace overstruck characters
  if(isOverstrike()){
    end=overstruck(start,end,text,n);
    }

  // Replace text
  replaceText(start,end-start,text,n,notify);
//  moveCursor(start+n,notify);


  if(repsel){ killSelection(notify); }
  setCursorPos(start+n,notify);
  makePositionVisible(cursorpos);
  setAnchorPos(cursorpos);
  flashMatching();
  }
*/

// Insert text at cursor
void FXText::enterText(const FXchar *text,FXint n,FXbool notify){
  FXint start=cursorpos;
  FXint end=cursorpos;

  // Replace selected characters
  if(isPosSelected(cursorpos)){
    start=selstartpos;
    end=selendpos;
    }

  // Replace overstruck characters
  if(isOverstrike()){
    end=overstruck(start,end,text,n);
    }

  // Replace text
  replaceText(start,end-start,text,n,notify);
  moveCursor(start+n,notify);
  }


// Insert text at cursor
void FXText::enterText(const FXString& text,FXbool notify){
  enterText(text.text(),text.length(),notify);
  }


/*******************************************************************************/


// Select all text
FXbool FXText::selectAll(FXbool notify){
  return setSelection(0,length,notify);
  }


// Set selection
FXbool FXText::setSelection(FXint pos,FXint len,FXbool notify){
  FXDragType types[4]={stringType,textType,utf8Type,utf16Type};
  register FXint ss=validPos(pos);
  register FXint se=validPos(pos+len);
  if(selstartpos!=ss || selendpos!=se){
    FXint what[2];

    // Update affected areas
    if(se<=selstartpos || selendpos<=ss){
      updateRange(selstartpos,selendpos);
      updateRange(ss,se);
      }
    else{
      updateRange(ss,selstartpos);
      updateRange(selendpos,se);
      }

    // Update selection
    selstartpos=ss;
    selendpos=se;

    // Acquire selection
    if(selstartpos<selendpos){
      if(!hasSelection()) acquireSelection(types,4);
      if(notify && target){
        what[0]=selstartpos;
        what[1]=selendpos-selstartpos;
        target->tryHandle(this,FXSEL(SEL_SELECTED,message),(void*)what);
        }
      }

    // Release selection
    else{
      if(hasSelection()) releaseSelection();
      if(notify && target){
        what[0]=selstartpos;
        what[1]=selendpos-selstartpos;
        target->tryHandle(this,FXSEL(SEL_DESELECTED,message),(void*)what);
        }
      }
    return true;
    }
  return false;
  }


// Extend selection
FXbool FXText::extendSelection(FXint pos,FXuint select,FXbool notify){
  register FXint p=validPos(pos),ss=0,se=0;
  switch(select){
    case SelectChars:                   // Selecting characters
      if(p<=anchorpos){
        ss=p;
        se=anchorpos;
        }
      else{
        ss=anchorpos;
        se=p;
        }
      break;
    case SelectWords:                   // Selecting words
      if(p<=anchorpos){
        ss=wordStart(p);
        se=wordEnd(anchorpos);
        }
      else{
        ss=wordStart(anchorpos);
        se=wordEnd(p);
        }
      break;
    case SelectRows:                    // Selecting rows
      if(p<=anchorpos){
        ss=rowStart(p);
        se=nextRow(anchorpos);
        }
      else{
        ss=rowStart(anchorpos);
        se=nextRow(p);
        }
      break;
    case SelectLines:                   // Selecting lines
      if(p<=anchorpos){
        ss=lineStart(p);
        se=nextLine(anchorpos);
        }
      else{
        ss=lineStart(anchorpos);
        se=nextLine(p);
        }
      break;
    }
  return setSelection(ss,se-ss,notify);
  }


// Kill the selection
FXbool FXText::killSelection(FXbool notify){
  if(selstartpos<selendpos){
    FXint what[2];
    if(notify && target){
      what[0]=selstartpos;
      what[1]=selendpos-selstartpos;
      target->tryHandle(this,FXSEL(SEL_DESELECTED,message),(void*)what);
      }
    if(hasSelection()) releaseSelection();
    updateRange(selstartpos,selendpos);
    selstartpos=0;
    selendpos=0;
    return true;
    }
  return false;
  }


// Copy selection to clipboard
FXbool FXText::copySelection(){
  FXDragType types[4]={stringType,textType,utf8Type,utf16Type};
  if(selstartpos<selendpos){
    if(acquireClipboard(types,ARRAYNUMBER(types))){
      extractText(clipped,selstartpos,selendpos-selstartpos);
      return true;
      }
    }
  return false;
  }


// Copy selection to clipboard and delete it
FXbool FXText::cutSelection(FXbool notify){
  if(copySelection()){
    return deleteSelection(notify);
    }
  return false;
  }


// Delete selection
FXbool FXText::deleteSelection(FXbool notify){
  if(selstartpos<selendpos){
    removeText(selstartpos,selendpos-selstartpos,notify);
    moveCursor(selstartpos,notify);
    return true;
    }
  return false;
  }


// Replace selection
FXbool FXText::replaceSelection(const FXchar *text,FXint n,FXbool notify){
  if(selstartpos<selendpos){
    replaceText(selstartpos,selendpos-selstartpos,text,n,notify);
    moveCursor(selstartpos+n,notify);
    return true;
    }
  return false;
  }


// Replace selection by other text
FXbool FXText::replaceSelection(const FXString& text,FXbool notify){
  return replaceSelection(text.text(),text.length(),notify);
  }


// Delete pending selection
FXbool FXText::deletePendingSelection(FXbool notify){
  return isPosSelected(cursorpos) && deleteSelection(notify);
  }


// Paste primary selection
FXbool FXText::pasteSelection(FXbool notify){

  // Avoid paste inside selection
  if(selstartpos==selendpos || cursorpos<=selstartpos || selendpos<=cursorpos){
    FXint start=cursorpos;
    FXint end=cursorpos;
    FXString string;

    // First, try UTF-8
    if(getDNDData(FROM_SELECTION,utf8Type,string)){
      if(isOverstrike()){
        end=overstruck(start,end,string.text(),string.length());
        }
      replaceText(start,end-start,string,notify);
      makePositionVisible(cursorpos);
      setCursorPos(cursorpos,notify);
      setAnchorPos(cursorpos);
      flashMatching();
      return true;
      }

    // Next, try UTF-16
    if(getDNDData(FROM_SELECTION,utf16Type,string)){
      if(isOverstrike()){
        end=overstruck(start,end,string.text(),string.length());
        }
      replaceText(start,end-start,string,notify);
      makePositionVisible(cursorpos);
      setCursorPos(cursorpos,notify);
      setAnchorPos(cursorpos);
      flashMatching();
      return true;
      }

    // Finally, try good old 8859-1
    if(getDNDData(FROM_SELECTION,stringType,string)){
      if(isOverstrike()){
        end=overstruck(start,end,string.text(),string.length());
        }
      replaceText(start,end-start,string,notify);
      makePositionVisible(cursorpos);
      setCursorPos(cursorpos,notify);
      setAnchorPos(cursorpos);
      flashMatching();
      return true;
      }
    }
  return false;
  }


// Paste clipboard
FXbool FXText::pasteClipboard(FXbool notify){
  FXString string;

  // First, try UTF-8
  if(getDNDData(FROM_CLIPBOARD,utf8Type,string)){
#ifdef WIN32
    dosToUnix(string);
#endif
    enterText(string,notify);
    return true;
    }

  // Next, try UTF-16
  if(getDNDData(FROM_CLIPBOARD,utf16Type,string)){
#ifdef WIN32
    dosToUnix(string);
#endif
    enterText(string,notify);
    return true;
    }

  // Next, try good old Latin-1
  if(getDNDData(FROM_CLIPBOARD,stringType,string)){
#ifdef WIN32
    dosToUnix(string);
#endif
    enterText(string,notify);
    return true;
    }
  return false;
  }


// Set highlight
FXbool FXText::setHighlight(FXint pos,FXint len){
  register FXint hs=validPos(pos);
  register FXint he=validPos(pos+len);
  if(hs!=hilitestartpos || he!=hiliteendpos){
    if(he<=hilitestartpos || hiliteendpos<=hs){
      updateRange(hilitestartpos,hiliteendpos);
      updateRange(hs,he);
      }
    else{
      updateRange(hs,hilitestartpos);
      updateRange(hiliteendpos,he);
      }
    hilitestartpos=hs;
    hiliteendpos=he;
    return true;
    }
  return false;
  }


// Unhighlight the text
FXbool FXText::killHighlight(){
  if(hilitestartpos<hiliteendpos){
    updateRange(hilitestartpos,hiliteendpos);
    hilitestartpos=0;
    hiliteendpos=0;
    return true;
    }
  return false;
  }

/*******************************************************************************/

// Draw fragment of text in given style
void FXText::drawBufferText(FXDCWindow& dc,FXint x,FXint y,FXint,FXint,FXint pos,FXint n,FXuint style) const {
  register FXuint index=(style&STYLE_MASK);
  register FXuint usedstyle=style;                                              // Style flags from style buffer
  register FXColor color;
  FXchar str[2];
  color=0;
  if(hilitestyles && index){                                                    // Get colors from style table
    usedstyle=hilitestyles[index-1].style;                                      // Style flags now from style table
    if(style&STYLE_SELECTED) color=hilitestyles[index-1].selectForeColor;
    else if(style&STYLE_HILITE) color=hilitestyles[index-1].hiliteForeColor;
    if(color==0) color=hilitestyles[index-1].normalForeColor;                   // Fall back on normal foreground color
    }
  if(color==0){                                                                 // Fall back to default style
    if(style&STYLE_SELECTED) color=seltextColor;
    else if(style&STYLE_HILITE) color=hilitetextColor;
    if(color==0) color=textColor;                                               // Fall back to normal text color
    }
  dc.setForeground(color);
  if(style&STYLE_CONTROL){
    y+=font->getFontAscent();
    str[0]='^';
    while(pos<gapstart && 0<n){
      str[1]=buffer[pos]|0x40;
      dc.drawText(x,y,str,2);
      if(usedstyle&STYLE_BOLD) dc.drawText(x+1,y,str,2);
      x+=font->getTextWidth(str,2);
      pos++;
      n--;
      }
    while(0<n){
      str[1]=buffer[pos-gapstart+gapend]|0x40;
      dc.drawText(x,y,str,2);
      if(usedstyle&STYLE_BOLD) dc.drawText(x+1,y,str,2);
      x+=font->getTextWidth(str,2);
      pos++;
      n--;
      }
    }
  else{
    y+=font->getFontAscent();
    if(pos+n<=gapstart){
      dc.drawText(x,y,&buffer[pos],n);
      if(usedstyle&STYLE_BOLD) dc.drawText(x+1,y,&buffer[pos],n);
      }
    else if(pos>=gapstart){
      dc.drawText(x,y,&buffer[pos-gapstart+gapend],n);
      if(usedstyle&STYLE_BOLD) dc.drawText(x+1,y,&buffer[pos-gapstart+gapend],n);
      }
    else{
      dc.drawText(x,y,&buffer[pos],gapstart-pos);
      if(usedstyle&STYLE_BOLD) dc.drawText(x+1,y,&buffer[pos],gapstart-pos);
      x+=font->getTextWidth(&buffer[pos],gapstart-pos);
      dc.drawText(x,y,&buffer[gapend],pos+n-gapstart);
      if(usedstyle&STYLE_BOLD) dc.drawText(x+1,y,&buffer[gapend],pos+n-gapstart);
      }
    }
  }


// Fill fragment of background in given style
void FXText::fillBufferRect(FXDCWindow& dc,FXint x,FXint y,FXint w,FXint h,FXuint style) const {
  register FXuint index=(style&STYLE_MASK);
  register FXuint usedstyle=style;                                              // Style flags from style buffer
  register FXColor bgcolor,fgcolor;
  bgcolor=fgcolor=0;
  if(hilitestyles && index){                                                    // Get colors from style table
    usedstyle=hilitestyles[index-1].style;                                      // Style flags now from style table
    if(style&STYLE_SELECTED){
      bgcolor=hilitestyles[index-1].selectBackColor;
      fgcolor=hilitestyles[index-1].selectForeColor;
      }
    else if(style&STYLE_HILITE){
      bgcolor=hilitestyles[index-1].hiliteBackColor;
      fgcolor=hilitestyles[index-1].hiliteForeColor;
      }
    else if(style&STYLE_ACTIVE){
      bgcolor=hilitestyles[index-1].activeBackColor;
      }
    else{
      bgcolor=hilitestyles[index-1].normalBackColor;
      }
    if(fgcolor==0){                                                             // Fall back to normal foreground color
      fgcolor=hilitestyles[index-1].normalForeColor;
      }
    }
  if(bgcolor==0){                                                               // Fall back to default background colors
    if(style&STYLE_SELECTED) bgcolor=selbackColor;
    else if(style&STYLE_HILITE) bgcolor=hilitebackColor;
    else if(style&STYLE_ACTIVE) bgcolor=activebackColor;
    else bgcolor=backColor;
    }
  if(fgcolor==0){                                                               // Fall back to default foreground colors
    if(style&STYLE_SELECTED) fgcolor=seltextColor;
    else if(style&STYLE_HILITE) fgcolor=hilitetextColor;
    if(fgcolor==0) fgcolor=textColor;                                           // Fall back to text color
    }
  dc.setForeground(bgcolor);
  dc.fillRectangle(x,y,w,h);
  if(usedstyle&STYLE_UNDERLINE){
    dc.setForeground(fgcolor);
    dc.fillRectangle(x,y+font->getFontAscent()+1,w,1);
    }
  if(usedstyle&STYLE_STRIKEOUT){
    dc.setForeground(fgcolor);
    dc.fillRectangle(x,y+font->getFontAscent()/2,w,1);
    }
  }


// Obtain text style at position pos; note pos may be outside of text
// to allow for rectangular selections!
FXuint FXText::styleOf(FXint beg,FXint end,FXint row,FXint col,FXint pos) const {
  register FXuint s=0;
  register FXchar c;

  // Current active line
  if((row==cursorrow) && (options&TEXT_SHOWACTIVE)) s|=STYLE_ACTIVE;

  // Selected part of text
  if(selstartpos<=pos && pos<selendpos) s|=STYLE_SELECTED;

  //if(10<=col && col<15) s|=STYLE_SELECTED;

  // Highlighted part of text
  if(hilitestartpos<=pos && pos<hiliteendpos) s|=STYLE_HILITE;

  // Blank part of line
  if(pos<end){

    // Special style for control characters
    c=getByte(pos);

    // Get value from style buffer
    if(sbuffer) s|=getStyle(pos);

    // Tabs, spaces, newlines are just fill
    if(c!='\t' && c!=' ' && c!='\n'){

      // Get special style for control codes
      if((FXuchar)c < ' ') s|=STYLE_CONTROL;

      // Text
      s|=STYLE_TEXT;
      }
    }
  return s;
  }


// Draw the cursor
void FXText::drawCursor(FXuint state){
  if((state^flags)&FLAG_CARET){
    if(xid){
      FXDCWindow dc(this);
      if(state&FLAG_CARET)
        paintCursor(dc);
      else
        eraseCursor(dc);
      }
    flags^=FLAG_CARET;
    }
  }


// Paint cursor glyph
void FXText::paintCursor(FXDCWindow& dc) const {
  FXint th,tw,cursorx,cursory; FXwchar c;
  th=font->getFontHeight();
  cursory=getVisibleY()+margintop+pos_y+cursorrow*th;
  if(getVisibleY()+margintop<cursory+th && cursory<=getVisibleY()+getVisibleHeight()+marginbottom){
    tw=font->getCharWidth((cursorpos<length) && ((c=getChar(cursorpos))>=' ')?c:' ');
    cursorx=getVisibleX()+marginleft+pos_x+lineWidth(cursorstartpos,cursorpos-cursorstartpos)-1;
    if(getVisibleX()<=cursorx+tw+2 && cursorx-2<=getVisibleX()+getVisibleWidth()){
      dc.setClipRectangle(getVisibleX(),getVisibleY(),getVisibleWidth(),getVisibleHeight());
      if(0<dc.getClipWidth() && 0<dc.getClipHeight()){
        dc.setForeground(cursorColor);
        if(options&TEXT_OVERSTRIKE){
          dc.drawRectangle(cursorx,cursory,tw,th-1);
          }
        else{
          dc.fillRectangle(cursorx,cursory,2,th);
          dc.fillRectangle(cursorx-2,cursory,6,1);
          dc.fillRectangle(cursorx-2,cursory+th-1,6,1);
          }
        }
      }
    }
  }


// Erase cursor glyph
void FXText::eraseCursor(FXDCWindow& dc) const {
  FXint th,tw,cursorx,cursory,cx,cy,ch,cw; FXwchar c;
  th=font->getFontHeight();
  cursory=getVisibleY()+margintop+pos_y+cursorrow*th;
  if(getVisibleY()+margintop<cursory+th && cursory<=getVisibleY()+getVisibleHeight()+marginbottom){
    tw=font->getCharWidth((cursorpos<length) && ((c=getChar(cursorpos))>=' ')?c:' ');
    cursorx=getVisibleX()+marginleft+pos_x+lineWidth(cursorstartpos,cursorpos-cursorstartpos)-1;
    if(getVisibleX()<=cursorx+tw+2 && cursorx-2<=getVisibleX()+getVisibleWidth()){
      dc.setClipRectangle(getVisibleX(),getVisibleY(),getVisibleWidth(),getVisibleHeight());
      if(0<dc.getClipWidth() && 0<dc.getClipHeight()){
        dc.setFont(font);
        dc.setForeground(backColor);
        dc.fillRectangle(cursorx-2,cursory,tw+4,th);
        cx=FXMAX(cursorx-2,getVisibleX()+marginleft);
        cy=getVisibleY()+margintop;
        cw=FXMIN(cursorx+tw+2,getVisibleX()+getVisibleWidth()-marginright)-cx;
        ch=getVisibleHeight()-margintop-marginbottom;
        dc.setClipRectangle(cx,cy,cw,ch);
        FXASSERT(toprow<=cursorrow && cursorrow<toprow+nvisrows);
        drawTextRow(dc,cursorrow);
        }
      }
    }
  }


// Erase cursor overhang outside of margins
void FXText::eraseCursorOverhang(){
  FXint th,tw,cursorx,cursory; FXwchar c;
  th=font->getFontHeight();
  cursory=getVisibleY()+margintop+pos_y+cursorrow*th;
  if(getVisibleY()+margintop<cursory+th && cursory<=getVisibleY()+getVisibleHeight()+marginbottom){
    tw=font->getCharWidth((cursorpos<length) && ((c=getChar(cursorpos))>=' ')?c:' ');
    cursorx=getVisibleX()+marginleft+pos_x+lineWidth(cursorstartpos,cursorpos-cursorstartpos)-1;
    if(getVisibleX()<=cursorx+tw+2 && cursorx-2<=getVisibleX()+getVisibleWidth()){
      FXDCWindow dc(this);
      if(cursorx-2<=getVisibleX()+marginleft && getVisibleX()<=cursorx+tw+2){
        dc.setForeground(backColor);
        dc.fillRectangle(getVisibleX(),cursory,marginleft,th);
        }
      if(getVisibleX()+getVisibleWidth()-marginright<=cursorx+tw+2 && cursorx-2<=getVisibleX()+getVisibleWidth()){
        dc.setForeground(backColor);
        dc.fillRectangle(getVisibleX()+getVisibleWidth()-marginright,cursory,marginright,th);
        }
      if(cursory<=getVisibleY()+margintop && getVisibleY()<=cursory+th){
        dc.setForeground(backColor);
        dc.fillRectangle(cursorx-2,getVisibleY(),tw+4,margintop);
        }
      if(getVisibleY()+getVisibleHeight()-marginbottom<=cursory+th && cursory<getVisibleY()+getVisibleHeight()){
        dc.setForeground(backColor);
        dc.fillRectangle(cursorx-2,getVisibleY()+getVisibleHeight()-marginbottom,tw+4,marginbottom);
        }
      }
    }
  }

// FIXME
// Runs should preferably be whole combining sequence
// Deal with non-rectangular selections.


// Draw partial text line [positions fm...to] with correct style
void FXText::drawTextRow(FXDCWindow& dc,FXint row) const {
  register FXint linebeg=visrows[row-toprow];
  register FXint lineend=visrows[row-toprow+1];
  register FXint linebreak=lineend;
  register FXint th=font->getFontHeight();
  register FXint tx=pos_x+getVisibleX()+marginleft;
  register FXint ty=pos_y+getVisibleY()+margintop+row*th;
  register FXint tw=0;
  register FXint edge=tx;
  register FXuint curstyle;
  register FXuint newstyle;
  register FXint cw,sp,sc,ep,ec;
  register FXwchar cc;

  FXASSERT(toprow<=row && row<toprow+nvisrows);
  FXASSERT(0<=linebeg && lineend<=length);

  // Back off past break-character, i.e. space or newline (if any)
  if(linebeg<linebreak && Ascii::isSpace(getByte(linebreak-1))) linebreak--;

  // If in wrap mode, count columns from true start of line till wrapped
  // start of the line, for rectangular selections
  //sc=(options&TEXT_WORDWRAP) && haverectselection ? countCols(lineStart(linebeg),linebeg) : 0;

  sc=0;

  // Scan ahead till until we hit the end or the left edge
  for(sp=linebeg; ; sc++){       // FIXME Not quite, if we count >1 columns/char sometimes...
    cc=(sp<linebreak) ? getChar(sp) : ' ';
    cw=charWidth(cc,tx-edge);
    if(tx+cw>=dc.getClipX()) break;
    if(sp<linebreak) sp+=getCharLen(sp);
    tx+=cw;
    }

  // First style to display
  curstyle=styleOf(linebeg,lineend,row,sc,sp);

  // Draw until we hit the end or the right edge
  for(ep=sp,ec=sc; ; ec++){
    newstyle=styleOf(linebeg,lineend,row,ec,ep);
    if(newstyle!=curstyle){
      fillBufferRect(dc,tx,ty,tw,th,curstyle);
      if(curstyle&STYLE_TEXT) drawBufferText(dc,tx,ty,tw,th,sp,ep-sp,curstyle);
      curstyle=newstyle;
      sp=ep;
      tx+=tw;
      tw=0;
      }
    cc=(ep<linebreak) ? getChar(ep) : ' ';
    cw=charWidth(cc,tx+tw-edge);
    if(tx+tw>=dc.getClipX()+dc.getClipWidth()) break;
    if(ep<linebreak) ep+=getCharLen(ep);
    tw+=cw;
    }

  // Draw unfinished fragment
  fillBufferRect(dc,tx,ty,tw,th,curstyle);
  if(curstyle&STYLE_TEXT) drawBufferText(dc,tx,ty,tw,th,sp,ep-sp,curstyle);
  }


// Repaint lines of text
void FXText::drawContents(FXDCWindow& dc) const {
  register FXint vx=getVisibleX();
  register FXint vy=getVisibleY();
  register FXint vw=getVisibleWidth();
  register FXint vh=getVisibleHeight();
  register FXint th,row,trow,brow;
  dc.setClipRectangle(vx,vy,vw,vh);
  dc.setForeground(backColor);
  if(dc.getClipY()<=vy+margintop){
    dc.fillRectangle(vx,vy,vw,margintop);
    }
  if(dc.getClipY()+dc.getClipHeight()>=vy+vh-marginbottom){
    dc.fillRectangle(vx,vy+vh-marginbottom,vw,marginbottom);
    }
  if(dc.getClipX()<vx+marginleft){
    dc.fillRectangle(vx,vy+margintop,marginleft,vh-margintop-marginbottom);
    }
  if(dc.getClipX()+dc.getClipWidth()>=vx+vw-marginright){
    dc.fillRectangle(vx+vw-marginright,vy+margintop,marginright,vh-margintop-marginbottom);
    }
  th=font->getFontHeight();
  trow=(dc.getClipY()-pos_y-vy-margintop)/th;
  brow=(dc.getClipY()+dc.getClipHeight()-pos_y-vy-margintop)/th;
  dc.setClipRectangle(vx+marginleft,vy+margintop,vw-marginright-marginleft,vh-margintop-marginbottom);
  if(trow<=toprow) trow=toprow;
  if(brow>=toprow+nvisrows) brow=toprow+nvisrows-1;
  for(row=trow; row<=brow; row++){
    drawTextRow(dc,row);
    }
  }


// Repaint line numbers
void FXText::drawNumbers(FXDCWindow& dc) const {
  register FXint vx=getVisibleX();
  register FXint vy=getVisibleY();
  register FXint vh=getVisibleHeight();
  register FXint tw,th,trow,brow,row,n;
  FXchar number[20];
  dc.setClipRectangle(0,vy,vx,vh);
  dc.setForeground(barColor);
  dc.fillRectangle(0,vy,vx,vh);
  dc.setForeground(numberColor);
  th=font->getFontHeight();
  trow=(dc.getClipY()-pos_y-vy-margintop)/th;
  brow=(dc.getClipY()+dc.getClipHeight()-pos_y-vy-margintop)/th;
  if(trow<=toprow) trow=toprow;
  if(brow>=toprow+nvisrows) brow=toprow+nvisrows;
  for(row=trow; row<=brow; row++){
    n=__snprintf(number,sizeof(number),"%d",row+1);
    tw=font->getTextWidth(number,n);
    dc.drawText(vx-tw,pos_y+vy+margintop+row*th+font->getFontAscent(),number,n);
    }
  }


// Repaint text range
void FXText::updateRange(FXint beg,FXint end) const {
  register FXint vx,vy,vw,b,e,tl,bl,fc,lc,lx,rx,ty,by;
  FXMINMAX(b,e,beg,end);
  if(b<=visrows[nvisrows] && visrows[0]<e && b<=e){
    if(b<visrows[0]) b=visrows[0];
    if(e>visrows[nvisrows]) e=visrows[nvisrows];
    vx=getVisibleX();
    vy=getVisibleY();
    vw=getVisibleWidth();
    tl=posToLine(b,0);
    bl=posToLine(e,tl);
    if(tl==bl){
      fc=b-visrows[tl];
      lc=e-visrows[tl];
      ty=pos_y+vy+margintop+(toprow+tl)*font->getFontHeight();
      by=ty+font->getFontHeight();
      lx=pos_x+vx+marginleft+lineWidth(visrows[tl],fc);
      if(e<=(visrows[tl+1]-1))
        rx=pos_x+vx+marginleft+lineWidth(visrows[tl],lc);
      else
        rx=vx+vw;
      }
    else{
      ty=pos_y+vy+margintop+(toprow+tl)*font->getFontHeight();
      by=pos_y+vy+margintop+(toprow+bl+1)*font->getFontHeight();
      lx=vx;
      rx=lx+vw;
      }
    update(lx,ty,rx-lx,by-ty);
    }
  }


// Draw the text
long FXText::onPaint(FXObject*,FXSelector,void* ptr){
  FXDCWindow dc(this,(FXEvent*)ptr);

  // Set font
  dc.setFont(font);

//dc.setForeground(FXRGB(255,0,0));
//dc.fillRectangle(0,0,width,height);

  // Paint text
  drawContents(dc);

  // Paint line numbers if turned on
  if(barwidth){
    drawNumbers(dc);
    }

  // Paint cursor
  if(flags&FLAG_CARET){
    paintCursor(dc);
    }
  return 1;
  }

/*******************************************************************************/

// Blink the cursor
long FXText::onBlink(FXObject*,FXSelector,void*){
  drawCursor(flags^FLAG_CARET);
  getApp()->addTimeout(this,ID_BLINK,getApp()->getBlinkSpeed());
  return 0;
  }


// Flash matching brace
long FXText::onFlash(FXObject*,FXSelector,void*){
  killHighlight();
  return 0;
  }

// Gained focus
long FXText::onFocusIn(FXObject* sender,FXSelector sel,void* ptr){
  FXScrollArea::onFocusIn(sender,sel,ptr);
  if(isEditable()){
    getApp()->addTimeout(this,ID_BLINK,getApp()->getBlinkSpeed());
    drawCursor(FLAG_CARET);
    }
  return 1;
  }


// Lost focus
long FXText::onFocusOut(FXObject* sender,FXSelector sel,void* ptr){
  FXScrollArea::onFocusOut(sender,sel,ptr);
  if(isEditable()){
    getApp()->removeTimeout(this,ID_BLINK);
    drawCursor(0);                                      // FIXME show insertion-caret?
    }
  flags|=FLAG_UPDATE;
  return 1;
  }

/*******************************************************************************/

// Update value from a message
long FXText::onCmdSetStringValue(FXObject*,FXSelector,void* ptr){
  setText(*((FXString*)ptr));
  return 1;
  }


// Obtain value from text
long FXText::onCmdGetStringValue(FXObject*,FXSelector,void* ptr){
  getText(*((FXString*)ptr));
  return 1;
  }

/*******************************************************************************/

// Set tip using a message
long FXText::onCmdSetTip(FXObject*,FXSelector,void* ptr){
  setTipText(*((FXString*)ptr));
  return 1;
  }


// Get tip using a message
long FXText::onCmdGetTip(FXObject*,FXSelector,void* ptr){
  *((FXString*)ptr)=getTipText();
  return 1;
  }


// Set help using a message
long FXText::onCmdSetHelp(FXObject*,FXSelector,void* ptr){
  setHelpText(*((FXString*)ptr));
  return 1;
  }


// Get help using a message
long FXText::onCmdGetHelp(FXObject*,FXSelector,void* ptr){
  *((FXString*)ptr)=getHelpText();
  return 1;
  }


// We were asked about tip text
long FXText::onQueryTip(FXObject* sender,FXSelector sel,void* ptr){
  if(FXScrollArea::onQueryTip(sender,sel,ptr)) return 1;
  if((flags&FLAG_TIP) && !tip.empty()){
    sender->handle(this,FXSEL(SEL_COMMAND,ID_SETSTRINGVALUE),(void*)&tip);
    return 1;
    }
  return 0;
  }


// We were asked about status text
long FXText::onQueryHelp(FXObject* sender,FXSelector sel,void* ptr){
  if(FXScrollArea::onQueryHelp(sender,sel,ptr)) return 1;
  if((flags&FLAG_HELP) && !help.empty()){
    sender->handle(this,FXSEL(SEL_COMMAND,ID_SETSTRINGVALUE),(void*)&help);
    return 1;
    }
  return 0;
  }


// Update somebody who wants to change the text
long FXText::onUpdIsEditable(FXObject* sender,FXSelector,void*){
  sender->handle(this,isEditable()?FXSEL(SEL_COMMAND,ID_ENABLE):FXSEL(SEL_COMMAND,ID_DISABLE),NULL);
  return 1;
  }


// Update somebody who works on the selection
long FXText::onUpdHaveSelection(FXObject* sender,FXSelector,void*){
  sender->handle(this,(selstartpos<selendpos)?FXSEL(SEL_COMMAND,ID_ENABLE):FXSEL(SEL_COMMAND,ID_DISABLE),NULL);
  return 1;
  }


// Update somebody who works on the selection and change the text
long FXText::onUpdHaveEditableSelection(FXObject* sender,FXSelector,void*){
  sender->handle(this,isEditable() && (selstartpos<selendpos)?FXSEL(SEL_COMMAND,ID_ENABLE):FXSEL(SEL_COMMAND,ID_DISABLE),NULL);
  return 1;
  }


// Start input method editor
long FXText::onIMEStart(FXObject* sender,FXSelector,void* ptr){
  if(isEditable()){
    if(getComposeContext()){
      FXint th=font->getFontHeight();
      FXint cursory=getVisibleY()+margintop+pos_y+cursorrow*th;
      if(getVisibleY()<=cursory+th && cursory<=getVisibleY()+getVisibleHeight()){
        FXint cursorx=getVisibleX()+marginleft+pos_x+lineWidth(cursorstartpos,cursorpos-cursorstartpos)-1;
        getComposeContext()->setSpot(cursorx,cursory);
        }
      }
    return 1;
    }
  return 0;
  }

/*******************************************************************************/

// Start a drag operation
long FXText::onBeginDrag(FXObject* sender,FXSelector sel,void* ptr){
  FXDragType types[4]={stringType,textType,utf8Type,utf16Type};
  if(!FXScrollArea::onBeginDrag(sender,sel,ptr)){
    beginDrag(types,ARRAYNUMBER(types));
    setDragCursor(getApp()->getDefaultCursor(DEF_DNDSTOP_CURSOR));
    }
  return 1;
  }


// End drag operation
long FXText::onEndDrag(FXObject* sender,FXSelector sel,void* ptr){
  if(!FXScrollArea::onEndDrag(sender,sel,ptr)){
    endDrag((didAccept()!=DRAG_REJECT));
    setDragCursor(getApp()->getDefaultCursor(DEF_TEXT_CURSOR));
    }
  return 1;
  }


// Dragged stuff around
long FXText::onDragged(FXObject* sender,FXSelector sel,void* ptr){
  if(!FXScrollArea::onDragged(sender,sel,ptr)){
    FXDragAction action=DRAG_COPY;
    if(isEditable()){
      if(isDropTarget()) action=DRAG_MOVE;
      if(((FXEvent*)ptr)->state&CONTROLMASK) action=DRAG_COPY;
      if(((FXEvent*)ptr)->state&SHIFTMASK) action=DRAG_MOVE;
      }
    handleDrag(((FXEvent*)ptr)->root_x,((FXEvent*)ptr)->root_y,action);
    action=didAccept();
    switch(action){
      case DRAG_MOVE:
        setDragCursor(getApp()->getDefaultCursor(DEF_DNDMOVE_CURSOR));
        break;
      case DRAG_COPY:
        setDragCursor(getApp()->getDefaultCursor(DEF_DNDCOPY_CURSOR));
        break;
      default:
        setDragCursor(getApp()->getDefaultCursor(DEF_DNDSTOP_CURSOR));
        break;
      }
    }
  return 1;
  }


// Handle drag-and-drop enter
long FXText::onDNDEnter(FXObject* sender,FXSelector sel,void* ptr){
  FXScrollArea::onDNDEnter(sender,sel,ptr);
  if(isEditable()){
    drawCursor(FLAG_CARET);
    }
  return 1;
  }


// Handle drag-and-drop leave
long FXText::onDNDLeave(FXObject* sender,FXSelector sel,void* ptr){
  FXScrollArea::onDNDLeave(sender,sel,ptr);
  stopAutoScroll();
  if(isEditable()){
    drawCursor(0);
    }
  return 1;
  }


// Handle drag-and-drop motion
long FXText::onDNDMotion(FXObject* sender,FXSelector sel,void* ptr){
  FXEvent* event=(FXEvent*)ptr;

  // Scroll into view
  if(startAutoScroll(event,true)) return 1;

  // Handled elsewhere
  if(FXScrollArea::onDNDMotion(sender,sel,ptr)) return 1;

  // Correct drop type
  if(offeredDNDType(FROM_DRAGNDROP,textType) || offeredDNDType(FROM_DRAGNDROP,stringType) || offeredDNDType(FROM_DRAGNDROP,utf8Type) || offeredDNDType(FROM_DRAGNDROP,utf16Type)){

    // Is target editable?
    if(isEditable()){
      FXDragAction action=inquireDNDAction();

      // Check for legal DND action
      if(action==DRAG_COPY || action==DRAG_MOVE){

        // Get the suggested drop position
        FXint pos=getPosAt(event->win_x,event->win_y);

        // Move cursor to new position
        setCursorPos(pos,true);

        // We don't accept a drop on the selection
        if(!isPosSelected(pos)){
          acceptDrop(DRAG_ACCEPT);
          }
        }
      }
    return 1;
    }

  // Didn't handle it here
  return 0;
  }


// Handle drag-and-drop drop
long FXText::onDNDDrop(FXObject* sender,FXSelector sel,void* ptr){

  // Stop scrolling
  stopAutoScroll();
  drawCursor(0);

  // Try handling it in base class first
  if(FXScrollArea::onDNDDrop(sender,sel,ptr)) return 1;

  // Should really not have gotten this if non-editable
  if(isEditable()){
    FXString string;
    FXString junk;

    // First, try UTF-8
    if(getDNDData(FROM_DRAGNDROP,utf8Type,string)){
      if(inquireDNDAction()==DRAG_MOVE){
        getDNDData(FROM_DRAGNDROP,deleteType,junk);
        }
      replaceText(cursorpos,0,string,true);
      setCursorPos(cursorpos,true);
      return 1;
      }

    // Next, try UTF-16
    if(getDNDData(FROM_DRAGNDROP,utf16Type,string)){
      if(inquireDNDAction()==DRAG_MOVE){
        getDNDData(FROM_DRAGNDROP,deleteType,junk);
        }
      replaceText(cursorpos,0,string,true);
      setCursorPos(cursorpos,true);
      return 1;
      }

    // Next, try good old Latin-1
    if(getDNDData(FROM_DRAGNDROP,textType,string)){
      if(inquireDNDAction()==DRAG_MOVE){
        getDNDData(FROM_DRAGNDROP,deleteType,junk);
        }
      replaceText(cursorpos,0,string,true);
      setCursorPos(cursorpos,true);
      return 1;
      }
    return 1;
    }
  return 0;
  }


// Service requested DND data
long FXText::onDNDRequest(FXObject* sender,FXSelector sel,void* ptr){
  FXEvent *event=(FXEvent*)ptr;

  // Perhaps the target wants to supply its own data
  if(FXScrollArea::onDNDRequest(sender,sel,ptr)) return 1;

  // Recognize the request?
  if(event->target==stringType || event->target==textType || event->target==utf8Type || event->target==utf16Type){
    FXString string;

    // Get selected fragment
    extractText(string,selstartpos,selendpos-selstartpos);

    // Return text of the selection as UTF-8
    if(event->target==utf8Type){
      setDNDData(FROM_DRAGNDROP,event->target,string);
      return 1;
      }

    // Return text of the selection translated to 8859-1
    if(event->target==stringType || event->target==textType){
      setDNDData(FROM_DRAGNDROP,event->target,string);
      return 1;
      }

    // Return text of the selection translated to UTF-16
    if(event->target==utf16Type){
      setDNDData(FROM_DRAGNDROP,event->target,string);
      return 1;
      }
    }

  // Delete dragged text, if editable
  if(event->target==deleteType){
    if(isEditable()){
      removeText(selstartpos,selendpos-selstartpos,true);
      }
    return 1;
    }

  return 0;
  }

/*******************************************************************************/

// We now really do have the selection
long FXText::onSelectionGained(FXObject* sender,FXSelector sel,void* ptr){
  FXScrollArea::onSelectionGained(sender,sel,ptr);
  return 1;
  }


// We lost the selection somehow
long FXText::onSelectionLost(FXObject* sender,FXSelector sel,void* ptr){
  FXScrollArea::onSelectionLost(sender,sel,ptr);
  if(target){
    FXint what[2];
    what[0]=selstartpos;
    what[1]=selendpos-selstartpos;
    target->tryHandle(this,FXSEL(SEL_DESELECTED,message),(void*)what);
    }
  updateRange(selstartpos,selendpos);
  selstartpos=0;
  selendpos=0;
  return 1;
  }


// Somebody wants our selection
long FXText::onSelectionRequest(FXObject* sender,FXSelector sel,void* ptr){
  FXEvent *event=(FXEvent*)ptr;

  // Perhaps the target wants to supply its own data for the selection
  if(FXScrollArea::onSelectionRequest(sender,sel,ptr)) return 1;

  // Recognize the request?
  if(event->target==stringType || event->target==textType || event->target==utf8Type || event->target==utf16Type){
    FXString string;

    // Get selected fragment
    extractText(string,selstartpos,selendpos-selstartpos);

    // Return text of the selection as UTF-8
    if(event->target==utf8Type){
      setDNDData(FROM_SELECTION,event->target,string);
      return 1;
      }

    // Return text of the selection translated to 8859-1
    if(event->target==stringType || event->target==textType){
      setDNDData(FROM_SELECTION,event->target,string);
      return 1;
      }

    // Return text of the selection translated to UTF-16
    if(event->target==utf16Type){
      setDNDData(FROM_SELECTION,event->target,string);
      return 1;
      }
    }
  return 0;
  }

/*******************************************************************************/

// We now really do have the selection
long FXText::onClipboardGained(FXObject* sender,FXSelector sel,void* ptr){
  FXScrollArea::onClipboardGained(sender,sel,ptr);
  return 1;
  }


// We lost the selection somehow
long FXText::onClipboardLost(FXObject* sender,FXSelector sel,void* ptr){
  FXScrollArea::onClipboardLost(sender,sel,ptr);
  clipped.clear();
  return 1;
  }


// Somebody wants our selection
long FXText::onClipboardRequest(FXObject* sender,FXSelector sel,void* ptr){
  FXEvent *event=(FXEvent*)ptr;

  // Try handling it in base class first
  if(FXScrollArea::onClipboardRequest(sender,sel,ptr)) return 1;

  // Requested data from clipboard
  if(event->target==stringType || event->target==textType || event->target==utf8Type || event->target==utf16Type){
    FXString string=clipped;

    // Expand newlines to CRLF on Windows
#ifdef WIN32
    unixToDos(string);
#endif

    // Return clipped text as as UTF-8
    if(event->target==utf8Type){
      setDNDData(FROM_CLIPBOARD,event->target,string);
      return 1;
      }

    // Return clipped text translated to 8859-1
    if(event->target==stringType || event->target==textType){
      setDNDData(FROM_CLIPBOARD,event->target,string);
      return 1;
      }

    // Return text of the selection translated to UTF-16
    if(event->target==utf16Type){
      setDNDData(FROM_CLIPBOARD,event->target,string);
      return 1;
      }
    }
  return 0;
  }

/*******************************************************************************/

// Pressed left button
long FXText::onLeftBtnPress(FXObject*,FXSelector,void* ptr){
  FXEvent* event=(FXEvent*)ptr;
  FXint pos;
  flags&=~FLAG_TIP;
  handle(this,FXSEL(SEL_FOCUS_SELF,0),ptr);
  if(isEnabled()){
    grab();
    if(target && target->tryHandle(this,FXSEL(SEL_LEFTBUTTONPRESS,message),ptr)) return 1;
    grabx=event->win_x-pos_x;
    graby=event->win_y-pos_y;
    if(event->click_count==1){          // Select characters
      pos=getPosAt(event->win_x,event->win_y);
      if(event->state&SHIFTMASK){
        moveCursorAndSelect(pos,SelectChars,true);
        }
      else{
        moveCursor(pos,true);
        }
      mode=MOUSE_CHARS;
      }
    else if(event->click_count==2){     // Select words
      pos=getPosContaining(event->win_x,event->win_y);
      moveCursorAndSelect(pos,SelectWords,true);
      mode=MOUSE_WORDS;
      }
    else{                               // Select lines
      pos=getPosContaining(event->win_x,event->win_y);
      moveCursorAndSelect(pos,SelectLines,true);
      mode=MOUSE_LINES;
      }
    flags&=~FLAG_UPDATE;
    return 1;
    }
  return 0;
  }


// Released left button
long FXText::onLeftBtnRelease(FXObject*,FXSelector,void* ptr){
  if(isEnabled()){
    ungrab();
    mode=MOUSE_NONE;
    stopAutoScroll();
    if(target && target->tryHandle(this,FXSEL(SEL_LEFTBUTTONRELEASE,message),ptr)) return 1;
    return 1;
    }
  return 0;
  }


// Pressed middle button
long FXText::onMiddleBtnPress(FXObject*,FXSelector,void* ptr){
  FXEvent* event=(FXEvent*)ptr;
  FXint pos;
  flags&=~FLAG_TIP;
  handle(this,FXSEL(SEL_FOCUS_SELF,0),ptr);
  if(isEnabled()){
    grab();
    if(target && target->tryHandle(this,FXSEL(SEL_MIDDLEBUTTONPRESS,message),ptr)) return 1;
    pos=getPosAt(event->win_x,event->win_y);
    setCursorPos(pos,true);
    setAnchorPos(cursorpos);
    if(isPosSelected(cursorpos)){
      mode=MOUSE_TRYDRAG;
      }
    flags&=~FLAG_UPDATE;
    return 1;
    }
  return 0;
  }


// Released middle button
long FXText::onMiddleBtnRelease(FXObject*,FXSelector,void* ptr){
  FXuint md=mode;
  if(isEnabled()){
    ungrab();
    stopAutoScroll();
    mode=MOUSE_NONE;
    if(target && target->tryHandle(this,FXSEL(SEL_MIDDLEBUTTONRELEASE,message),ptr)) return 1;
    if(md==MOUSE_DRAG){
      handle(this,FXSEL(SEL_ENDDRAG,0),ptr);
      }
    else{
      handle(this,FXSEL(SEL_COMMAND,ID_PASTE_MIDDLE),NULL);
      }
    return 1;
    }
  return 0;
  }


// Pressed right button
long FXText::onRightBtnPress(FXObject*,FXSelector,void* ptr){
  FXEvent* event=(FXEvent*)ptr;
  flags&=~FLAG_TIP;
  handle(this,FXSEL(SEL_FOCUS_SELF,0),ptr);
  if(isEnabled()){
    grab();
    if(target && target->tryHandle(this,FXSEL(SEL_RIGHTBUTTONPRESS,message),ptr)) return 1;
    grabx=event->win_x-pos_x;
    graby=event->win_y-pos_y;
    mode=MOUSE_SCROLL;
    flags&=~FLAG_UPDATE;
    return 1;
    }
  return 0;
  }


// Released right button
long FXText::onRightBtnRelease(FXObject*,FXSelector,void* ptr){
  if(isEnabled()){
    ungrab();
    mode=MOUSE_NONE;
    if(target && target->tryHandle(this,FXSEL(SEL_RIGHTBUTTONRELEASE,message),ptr)) return 1;
    return 1;
    }
  return 0;
  }


// Handle real or simulated mouse motion
long FXText::onMotion(FXObject*,FXSelector,void* ptr){
  FXEvent* event=(FXEvent*)ptr;
  switch(mode){
    case MOUSE_CHARS:
      if(startAutoScroll(event,false)) return 1;
      if((fxabs(event->win_x-grabx-pos_x)>getApp()->getDragDelta())||(fxabs(event->win_y-graby-pos_y)>getApp()->getDragDelta())){
        setCursorPos(getPosAt(event->win_x,event->win_y),true);
        extendSelection(cursorpos,SelectChars,true);
        }
      return 1;
    case MOUSE_WORDS:
      if(startAutoScroll(event,false)) return 1;
      if((fxabs(event->win_x-grabx-pos_x)>getApp()->getDragDelta())||(fxabs(event->win_y-graby-pos_y)>getApp()->getDragDelta())){
        setCursorPos(getPosContaining(event->win_x,event->win_y),true);
        extendSelection(cursorpos,SelectWords,true);
        }
      return 1;
    case MOUSE_LINES:
      if(startAutoScroll(event,false)) return 1;
      if((fxabs(event->win_x-grabx-pos_x)>getApp()->getDragDelta())||(fxabs(event->win_y-graby-pos_y)>getApp()->getDragDelta())){
        setCursorPos(getPosAt(event->win_x,event->win_y),true);
        extendSelection(cursorpos,SelectLines,true);
        }
      return 1;
    case MOUSE_SCROLL:
      setPosition(event->win_x-grabx,event->win_y-graby);
      return 1;
    case MOUSE_DRAG:
      handle(this,FXSEL(SEL_DRAGGED,0),ptr);
      return 1;
    case MOUSE_TRYDRAG:
      if(event->moved){
        mode=MOUSE_NONE;
        if(handle(this,FXSEL(SEL_BEGINDRAG,0),ptr)){
          mode=MOUSE_DRAG;
          }
        }
      return 1;
    }
  return 0;
  }


// Autoscroll timer fired; autoscrolling hysteresis is based on movement
// relative to the original document position of the click, in case the
// click-position is close to the autoscrolling fudge-border.
long FXText::onAutoScroll(FXObject* sender,FXSelector sel,void* ptr){
  FXEvent* event=(FXEvent*)ptr;
  FXScrollArea::onAutoScroll(sender,sel,ptr);
  switch(mode){
    case MOUSE_CHARS:
      if((fxabs(event->win_x-grabx-pos_x)>getApp()->getDragDelta())||(fxabs(event->win_y-graby-pos_y)>getApp()->getDragDelta())){
        setCursorPos(getPosAt(event->win_x,event->win_y),true);
        extendSelection(cursorpos,SelectChars,true);
        }
      return 1;
    case MOUSE_WORDS:
      if((fxabs(event->win_x-grabx-pos_x)>getApp()->getDragDelta())||(fxabs(event->win_y-graby-pos_y)>getApp()->getDragDelta())){
        setCursorPos(getPosContaining(event->win_x,event->win_y),true);
        extendSelection(cursorpos,SelectWords,true);
        }
      return 1;
    case MOUSE_LINES:
      if((fxabs(event->win_x-grabx-pos_x)>getApp()->getDragDelta())||(fxabs(event->win_y-graby-pos_y)>getApp()->getDragDelta())){
        setCursorPos(getPosAt(event->win_x,event->win_y),true);
        extendSelection(cursorpos,SelectLines,true);
        }
      return 1;
    }
  return 0;
  }


// The widget lost the grab for some reason
long FXText::onUngrabbed(FXObject* sender,FXSelector sel,void* ptr){
  FXScrollArea::onUngrabbed(sender,sel,ptr);
  mode=MOUSE_NONE;
  flags|=FLAG_UPDATE;
  stopAutoScroll();
  return 1;
  }

/*******************************************************************************/

// Keyboard press
long FXText::onKeyPress(FXObject*,FXSelector,void* ptr){
  FXEvent* event=(FXEvent*)ptr;
  flags&=~FLAG_TIP;
  if(isEnabled()){
    FXTRACE((200,"%s::onKeyPress keysym=0x%04x state=%04x\n",getClassName(),event->code,event->state));
    if(target && target->tryHandle(this,FXSEL(SEL_KEYPRESS,message),ptr)) return 1;
    flags&=~FLAG_UPDATE;
    switch(event->code){
      case KEY_Shift_L:
      case KEY_Shift_R:
      case KEY_Control_L:
      case KEY_Control_R:
        if(mode==MOUSE_DRAG){handle(this,FXSEL(SEL_DRAGGED,0),ptr);}
        return 1;
      case KEY_Up:
      case KEY_KP_Up:
        if(event->state&CONTROLMASK){
          handle(this,FXSEL(SEL_COMMAND,ID_SCROLL_UP),NULL);
          }
        else if(event->state&SHIFTMASK){
          handle(this,FXSEL(SEL_COMMAND,ID_CURSOR_SHIFT_UP),NULL);
          }
        else{
          handle(this,FXSEL(SEL_COMMAND,ID_CURSOR_UP),NULL);
          }
        break;
      case KEY_Down:
      case KEY_KP_Down:
        if(event->state&CONTROLMASK){
          handle(this,FXSEL(SEL_COMMAND,ID_SCROLL_DOWN),NULL);
          }
        else if(event->state&SHIFTMASK){
          handle(this,FXSEL(SEL_COMMAND,ID_CURSOR_SHIFT_DOWN),NULL);
          }
        else{
          handle(this,FXSEL(SEL_COMMAND,ID_CURSOR_DOWN),NULL);
          }
        break;
      case KEY_Left:
      case KEY_KP_Left:
        if(event->state&CONTROLMASK){
          if(event->state&SHIFTMASK){
            handle(this,FXSEL(SEL_COMMAND,ID_CURSOR_SHIFT_WORD_LEFT),NULL);
            }
          else{
            handle(this,FXSEL(SEL_COMMAND,ID_CURSOR_WORD_LEFT),NULL);
            }
          }
        else{
          if(event->state&SHIFTMASK){
            handle(this,FXSEL(SEL_COMMAND,ID_CURSOR_SHIFT_LEFT),NULL);
            }
          else{
            handle(this,FXSEL(SEL_COMMAND,ID_CURSOR_LEFT),NULL);
            }
          }
        break;
      case KEY_Right:
      case KEY_KP_Right:
        if(event->state&CONTROLMASK){
          if(event->state&SHIFTMASK){
            handle(this,FXSEL(SEL_COMMAND,ID_CURSOR_SHIFT_WORD_RIGHT),NULL);
            }
          else{
            handle(this,FXSEL(SEL_COMMAND,ID_CURSOR_WORD_RIGHT),NULL);
            }
          }
        else{
          if(event->state&SHIFTMASK){
            handle(this,FXSEL(SEL_COMMAND,ID_CURSOR_SHIFT_RIGHT),NULL);
            }
          else{
            handle(this,FXSEL(SEL_COMMAND,ID_CURSOR_RIGHT),NULL);
            }
          }
        break;
      case KEY_Home:
      case KEY_KP_Home:
        if(event->state&CONTROLMASK){
          if(event->state&SHIFTMASK){
            handle(this,FXSEL(SEL_COMMAND,ID_CURSOR_SHIFT_TOP),NULL);
            }
          else{
            handle(this,FXSEL(SEL_COMMAND,ID_CURSOR_TOP),NULL);
            }
          }
        else{
          if(event->state&SHIFTMASK){
            handle(this,FXSEL(SEL_COMMAND,ID_CURSOR_SHIFT_HOME),NULL);
            }
          else{
            handle(this,FXSEL(SEL_COMMAND,ID_CURSOR_HOME),NULL);
            }
          }
        break;
      case KEY_End:
      case KEY_KP_End:
        if(event->state&CONTROLMASK){
          if(event->state&SHIFTMASK){
            handle(this,FXSEL(SEL_COMMAND,ID_CURSOR_SHIFT_BOTTOM),NULL);
            }
          else{
            handle(this,FXSEL(SEL_COMMAND,ID_CURSOR_BOTTOM),NULL);
            }
          }
        else{
          if(event->state&SHIFTMASK){
            handle(this,FXSEL(SEL_COMMAND,ID_CURSOR_SHIFT_END),NULL);
            }
          else{
            handle(this,FXSEL(SEL_COMMAND,ID_CURSOR_END),NULL);
            }
          }
        break;
      case KEY_Page_Up:
      case KEY_KP_Page_Up:
        if(event->state&SHIFTMASK){
          handle(this,FXSEL(SEL_COMMAND,ID_CURSOR_SHIFT_PAGEUP),NULL);
          }
        else{
          handle(this,FXSEL(SEL_COMMAND,ID_CURSOR_PAGEUP),NULL);
          }
        break;
      case KEY_Page_Down:
      case KEY_KP_Page_Down:
        if(event->state&SHIFTMASK){
          handle(this,FXSEL(SEL_COMMAND,ID_CURSOR_SHIFT_PAGEDOWN),NULL);
          }
        else{
          handle(this,FXSEL(SEL_COMMAND,ID_CURSOR_PAGEDOWN),NULL);
          }
        break;
      case KEY_Insert:
      case KEY_KP_Insert:
        if(event->state&CONTROLMASK){
          handle(this,FXSEL(SEL_COMMAND,ID_COPY_SEL),NULL);
          }
        else if(event->state&SHIFTMASK){
          handle(this,FXSEL(SEL_COMMAND,ID_PASTE_SEL),NULL);
          }
        else{
          handle(this,FXSEL(SEL_COMMAND,ID_TOGGLE_OVERSTRIKE),NULL);
          }
        break;
      case KEY_Delete:
      case KEY_KP_Delete:
        if(event->state&CONTROLMASK){
          handle(this,FXSEL(SEL_COMMAND,ID_DELETE_WORD),NULL);
          }
        else if(event->state&SHIFTMASK){
          handle(this,FXSEL(SEL_COMMAND,ID_DELETE_EOL),NULL);
          }
        else{
          handle(this,FXSEL(SEL_COMMAND,ID_DELETE_CHAR),NULL);
          }
        break;
      case KEY_BackSpace:
        if(event->state&CONTROLMASK){
          handle(this,FXSEL(SEL_COMMAND,ID_BACKSPACE_WORD),NULL);
          }
        else if(event->state&SHIFTMASK){
          handle(this,FXSEL(SEL_COMMAND,ID_BACKSPACE_BOL),NULL);
          }
        else{
          handle(this,FXSEL(SEL_COMMAND,ID_BACKSPACE_CHAR),NULL);
          }
        break;
      case KEY_Return:
      case KEY_KP_Enter:
        if(event->state&CONTROLMASK){
          handle(this,FXSEL(SEL_COMMAND,ID_INSERT_NEWLINE_ONLY),NULL);
          }
        else if(event->state&SHIFTMASK){
          handle(this,FXSEL(SEL_COMMAND,ID_INSERT_NEWLINE_INDENT),NULL);
          }
        else{
          handle(this,FXSEL(SEL_COMMAND,ID_INSERT_NEWLINE),NULL);
          }
        break;
      case KEY_Tab:
      case KEY_KP_Tab:
        if(event->state&CONTROLMASK){
          handle(this,FXSEL(SEL_COMMAND,ID_INSERT_HARDTAB),NULL);
          }
        else{
          handle(this,FXSEL(SEL_COMMAND,ID_INSERT_TAB),NULL);
          }
        break;
      case KEY_a:
        if(!(event->state&CONTROLMASK)) goto ins;
        handle(this,FXSEL(SEL_COMMAND,ID_SELECT_ALL),NULL);
        break;
      case KEY_x:
        if(!(event->state&CONTROLMASK)) goto ins;
      case KEY_F20:                               // Sun Cut key
        handle(this,FXSEL(SEL_COMMAND,ID_CUT_SEL),NULL);
        break;
      case KEY_c:
        if(!(event->state&CONTROLMASK)) goto ins;
      case KEY_F16:                               // Sun Copy key
        handle(this,FXSEL(SEL_COMMAND,ID_COPY_SEL),NULL);
        break;
      case KEY_v:
        if(!(event->state&CONTROLMASK)) goto ins;
      case KEY_F18:                               // Sun Paste key
        handle(this,FXSEL(SEL_COMMAND,ID_PASTE_SEL),NULL);
        break;
      case KEY_k:
        if(!(event->state&CONTROLMASK)) goto ins;
        handle(this,FXSEL(SEL_COMMAND,ID_DELETE_LINE),NULL);
        break;
      case KEY_j:
        if(!(event->state&CONTROLMASK)) goto ins;
        handle(this,FXSEL(SEL_COMMAND,ID_JOIN_LINES),NULL);
        break;
      default:
ins:    if((event->state&(CONTROLMASK|ALTMASK)) || ((FXuchar)event->text[0]<32)) return 0;
        handle(this,FXSEL(SEL_COMMAND,ID_INSERT_STRING),(void*)event->text.text());
        break;
      }
    return 1;
    }
  return 0;
  }


// Keyboard release
long FXText::onKeyRelease(FXObject*,FXSelector,void* ptr){
  FXEvent* event=(FXEvent*)ptr;
  if(isEnabled()){
    FXTRACE((200,"%s::onKeyRelease keysym=0x%04x state=%04x\n",getClassName(),event->code,event->state));
    if(target && target->tryHandle(this,FXSEL(SEL_KEYRELEASE,message),ptr)) return 1;
    switch(event->code){
      case KEY_Shift_L:
      case KEY_Shift_R:
      case KEY_Control_L:
      case KEY_Control_R:
        if(mode==MOUSE_DRAG){handle(this,FXSEL(SEL_DRAGGED,0),ptr);}
        return 1;
      }
    }
  return 0;
  }

/*******************************************************************************/

// Move cursor to top of buffer
long FXText::onCmdCursorTop(FXObject*,FXSelector,void*){
  moveCursor(0,true);
  return 1;
  }


// Move cursor to bottom of buffer
long FXText::onCmdCursorBottom(FXObject*,FXSelector,void*){
  moveCursor(length,true);
  return 1;
  }


// Move cursor to begin of line
long FXText::onCmdCursorHome(FXObject*,FXSelector,void*){
  moveCursor(lineStart(cursorpos),true);
  return 1;
  }


// Move cursor to end of line
long FXText::onCmdCursorEnd(FXObject*,FXSelector,void*){
  moveCursor(lineEnd(cursorpos),true);
  return 1;
  }


// Process cursor right
long FXText::onCmdCursorRight(FXObject*,FXSelector,void*){
  moveCursor(cursorpos<length?inc(cursorpos):length,true);
  return 1;
  }


// Process cursor left
long FXText::onCmdCursorLeft(FXObject*,FXSelector,void*){
  moveCursor(0<cursorpos?dec(cursorpos):0,true);
  return 1;
  }


// Process cursor up
long FXText::onCmdCursorUp(FXObject*,FXSelector,void*){
  FXint col=(0<=prefcol) ? prefcol : cursorcol;
  moveCursor(posFromIndent(prevRow(cursorpos),col),true);
  prefcol=col;
  return 1;
  }


// Process cursor down
long FXText::onCmdCursorDown(FXObject*,FXSelector,void*){
  FXint col=(0<=prefcol) ? prefcol : cursorcol;
  moveCursor(posFromIndent(nextRow(cursorpos),col),true);
  prefcol=col;
  return 1;
  }


// Page up
long FXText::onCmdCursorPageUp(FXObject*,FXSelector,void*){
  FXint lines=getVisibleHeight()/font->getFontHeight();
  FXint col=(0<=prefcol) ? prefcol : cursorcol;
  setTopLine(prevRow(toppos,lines));
  moveCursor(posFromIndent(prevRow(cursorpos,lines),col),true);
  prefcol=col;
  return 1;
  }


// Page down
long FXText::onCmdCursorPageDown(FXObject*,FXSelector,void*){
  FXint lines=getVisibleHeight()/font->getFontHeight();
  FXint col=(0<=prefcol) ? prefcol : cursorcol;
  setTopLine(nextRow(toppos,lines));
  moveCursor(posFromIndent(nextRow(cursorpos,lines),col),true);
  prefcol=col;
  return 1;
  }


// Process cursor word left
long FXText::onCmdCursorWordLeft(FXObject*,FXSelector,void*){
  moveCursor(leftWord(cursorpos),true);
  return 1;
  }


// Process cursor word right
long FXText::onCmdCursorWordRight(FXObject*,FXSelector,void*){
  moveCursor(rightWord(cursorpos),true);
  return 1;
  }


// Process cursor to start of selection
long FXText::onCmdCursorSelStart(FXObject*,FXSelector,void*){
  if(selstartpos<=cursorpos && cursorpos<=selendpos){
    setAnchorPos(selendpos);
    setCursorPos(selstartpos,true);
    makePositionVisible(selstartpos);
    flashMatching();
    return 1;
    }
  getApp()->beep();
  return 1;
  }


// Process cursor to end of selection
long FXText::onCmdCursorSelEnd(FXObject*,FXSelector,void*){
  if(selstartpos<=cursorpos && cursorpos<=selendpos){
    setAnchorPos(selstartpos);
    setCursorPos(selendpos,true);
    makePositionVisible(selendpos);
    flashMatching();
    return 1;
    }
  getApp()->beep();
  return 1;
  }


// Process cursor shift+top
long FXText::onCmdCursorShiftTop(FXObject*,FXSelector,void*){
  moveCursorAndSelect(0,SelectChars,true);
  return 1;
  }


// Process cursor shift+bottom
long FXText::onCmdCursorShiftBottom(FXObject*,FXSelector,void*){
  moveCursorAndSelect(length,SelectChars,true);
  return 1;
  }


// Process cursor shift+home
long FXText::onCmdCursorShiftHome(FXObject*,FXSelector,void*){
  moveCursorAndSelect(lineStart(cursorpos),SelectChars,true);
  return 1;
  }


// Process cursor shift+end
long FXText::onCmdCursorShiftEnd(FXObject*,FXSelector,void*){
  moveCursorAndSelect(lineEnd(cursorpos),SelectChars,true);
  return 1;
  }


// Process cursor shift+right
long FXText::onCmdCursorShiftRight(FXObject*,FXSelector,void*){
  moveCursorAndSelect(cursorpos<length?inc(cursorpos):length,SelectChars,true);
  return 1;
  }


// Process cursor shift+left
long FXText::onCmdCursorShiftLeft(FXObject*,FXSelector,void*){
  moveCursorAndSelect(0<cursorpos?dec(cursorpos):0,SelectChars,true);
  return 1;
  }


// Process cursor shift+up
long FXText::onCmdCursorShiftUp(FXObject*,FXSelector,void*){
  FXint col=(0<=prefcol) ? prefcol : cursorcol;
  moveCursorAndSelect(posFromIndent(prevRow(cursorpos),col),SelectChars,true);
  prefcol=col;
  return 1;
  }


// Process cursor shift+down
long FXText::onCmdCursorShiftDown(FXObject*,FXSelector,void*){
  FXint col=(0<=prefcol) ? prefcol : cursorcol;
  moveCursorAndSelect(posFromIndent(nextRow(cursorpos),col),SelectChars,true);
  prefcol=col;
  return 1;
  }


// Process cursor shift+page up
long FXText::onCmdCursorShiftPageUp(FXObject*,FXSelector,void*){
  FXint lines=getVisibleHeight()/font->getFontHeight();
  FXint col=(0<=prefcol) ? prefcol : cursorcol;
  setTopLine(prevRow(toppos,lines));
  moveCursorAndSelect(posFromIndent(prevRow(cursorpos,lines),col),SelectChars,true);
  prefcol=col;
  return 1;
  }


// Process cursor shift+page down
long FXText::onCmdCursorShiftPageDown(FXObject*,FXSelector,void*){
  FXint lines=getVisibleHeight()/font->getFontHeight();
  FXint col=(0<=prefcol) ? prefcol : cursorcol;
  setTopLine(nextRow(toppos,lines));
  moveCursorAndSelect(posFromIndent(nextRow(cursorpos,lines),col),SelectChars,true);
  prefcol=col;
  return 1;
  }


// Process cursor shift+word left
long FXText::onCmdCursorShiftWordLeft(FXObject*,FXSelector,void*){
  moveCursorAndSelect(leftWord(cursorpos),SelectChars,true);
  return 1;
  }


// Process cursor shift+word right
long FXText::onCmdCursorShiftWordRight(FXObject*,FXSelector,void*){
  moveCursorAndSelect(rightWord(cursorpos),SelectChars,true);
  return 1;
  }


// Scroll up one line
long FXText::onCmdScrollUp(FXObject*,FXSelector,void*){
  setTopLine(prevRow(toppos,1));
  return 1;
  }


// Scroll down one line
long FXText::onCmdScrollDown(FXObject*,FXSelector,void*){
  setTopLine(nextRow(toppos,1));
  return 1;
  }


// Scroll to move cursor to top of screen
long FXText::onCmdScrollTop(FXObject*,FXSelector,void*){
  setTopLine(cursorpos);
  return 1;
  }


// Scroll to move cursor to bottom of screen
long FXText::onCmdScrollBottom(FXObject*,FXSelector,void*){
  setBottomLine(cursorpos);
  return 1;
  }


// Scroll to move cursor to center of screen
long FXText::onCmdScrollCenter(FXObject*,FXSelector,void*){
  setCenterLine(cursorpos);
  return 1;
  }


// Insert a string
long FXText::onCmdInsertString(FXObject*,FXSelector,void* ptr){
  if(isEditable()){
    enterText((const FXchar*)ptr,strlen((const FXchar*)ptr),true);
    return 1;
    }
  getApp()->beep();
  return 1;
  }


// Insert newline with optional autoindent
long FXText::onCmdInsertNewline(FXObject*,FXSelector,void*){
  if(options&TEXT_AUTOINDENT) return handle(this,FXSEL(SEL_COMMAND,ID_INSERT_NEWLINE_INDENT),NULL);
  return handle(this,FXSEL(SEL_COMMAND,ID_INSERT_NEWLINE_ONLY),NULL);
  }


// Insert newline only
long FXText::onCmdInsertNewlineOnly(FXObject*,FXSelector,void*){
  return handle(this,FXSEL(SEL_COMMAND,ID_INSERT_STRING),(void*)"\n");
  }


// Insert a character
long FXText::onCmdInsertNewlineIndent(FXObject*,FXSelector,void*){
  FXint pos=isPosSelected(cursorpos) ? selstartpos : cursorpos;
  FXint start=lineStart(pos);
  FXint n;
  FXString string;
  extractText(string,start,pos-start);
  n=string.find_first_not_of(" \t\v");
  if(0<=n) string.trunc(n);
  string.prepend('\n');
  return handle(this,FXSEL(SEL_COMMAND,ID_INSERT_STRING),(void*)string.text());
  }


// Insert optional soft-tab
long FXText::onCmdInsertTab(FXObject*,FXSelector,void*){
  if(options&TEXT_NO_TABS) return handle(this,FXSEL(SEL_COMMAND,ID_INSERT_SOFTTAB),NULL);
  return handle(this,FXSEL(SEL_COMMAND,ID_INSERT_HARDTAB),NULL);
  }


// Insert hard-tab
long FXText::onCmdInsertHardTab(FXObject*,FXSelector,void*){
  return handle(this,FXSEL(SEL_COMMAND,ID_INSERT_STRING),(void*)"\t");
  }


// Insert soft-tab
long FXText::onCmdInsertSoftTab(FXObject*,FXSelector,void*){
  FXint pos=isPosSelected(cursorpos) ? selstartpos : cursorpos;
  FXint indent=indentFromPos(lineStart(pos),pos);
  FXASSERT(0<tabcolumns && tabcolumns<MAXTABCOLUMNS);
  return handle(this,FXSEL(SEL_COMMAND,ID_INSERT_STRING),(void*)(spaces+MAXTABCOLUMNS+indent%tabcolumns-tabcolumns));
  }

/*******************************************************************************/

// Cut
long FXText::onCmdCutSel(FXObject*,FXSelector,void*){
  if(isEditable() && cutSelection(true)) return 1;
  getApp()->beep();
  return 1;
  }


// Copy
long FXText::onCmdCopySel(FXObject*,FXSelector,void*){
  copySelection();
  return 1;
  }


// Delete selection
long FXText::onCmdDeleteSel(FXObject*,FXSelector,void*){
  if(isEditable() && deleteSelection(true)) return 1;
  getApp()->beep();
  return 1;
  }


// Replace selection
long FXText::onCmdReplaceSel(FXObject*,FXSelector,void* ptr){
  if(isEditable() && replaceSelection((const FXchar*)ptr,strlen((const FXchar*)ptr),true)) return 1;
  getApp()->beep();
  return 1;
  }


// Paste clipboard
long FXText::onCmdPasteSel(FXObject*,FXSelector,void*){
  if(isEditable() && pasteClipboard(true)) return 1;
  getApp()->beep();
  return 1;
  }


// Paste selection
long FXText::onCmdPasteMiddle(FXObject*,FXSelector,void*){
  if(isEditable() && pasteSelection(true)) return 1;
  getApp()->beep();
  return 1;
  }


// Select character
long FXText::onCmdSelectChar(FXObject*,FXSelector,void*){
  setAnchorPos(cursorpos);
  extendSelection(inc(cursorpos),SelectChars,true);
  return 1;
  }


// Select Word
long FXText::onCmdSelectWord(FXObject*,FXSelector,void*){
  setAnchorPos(cursorpos);
  extendSelection(cursorpos,SelectWords,true);
  return 1;
  }


// Select Line
long FXText::onCmdSelectLine(FXObject*,FXSelector,void*){
  setAnchorPos(cursorpos);
  extendSelection(cursorpos,SelectLines,true);
  return 1;
  }


// Select text till matching character
long FXText::onCmdSelectMatching(FXObject*,FXSelector,void*){
  if(0<cursorpos){
    FXchar ch=getByte(cursorpos-1);
    FXint pos=findMatching(cursorpos-1,0,length,ch,1);
    if(0<=pos){
      if(cursorpos<=pos){
        setSelection(cursorpos-1,pos-cursorpos+2,true);
        setAnchorPos(cursorpos-1);
        setCursorPos(pos+1,true);
        }
      else{
        setSelection(pos,cursorpos-pos,true);
        setAnchorPos(cursorpos);
        setCursorPos(pos+1,true);
        }
      makePositionVisible(cursorpos);
      flashMatching();
      return 1;
      }
    }
  getApp()->beep();
  return 1;
  }


// Select entire enclosing block
long FXText::onCmdSelectBlock(FXObject*,FXSelector sel,void*){
  FXint what=FXSELID(sel)-ID_SELECT_BRACE;
  FXint level=1;
  FXint beg,end;
  while(1){
    beg=matchBackward(cursorpos-1,0,lefthand[what],righthand[what],level);
    end=matchForward(cursorpos,length,lefthand[what],righthand[what],level);
    if(0<=beg && beg<end){
      if(isPosSelected(beg) && isPosSelected(end+1)){ level++; continue; }
      setAnchorPos(beg);
      extendSelection(end+1,SelectChars,true);
      return 1;
      }
    getApp()->beep();
    break;
    }
  return 1;
  }


// Select All
long FXText::onCmdSelectAll(FXObject*,FXSelector,void*){
  setAnchorPos(0);
  extendSelection(length,SelectChars,true);
  return 1;
  }


// Deselect All
long FXText::onCmdDeselectAll(FXObject*,FXSelector,void*){
  killSelection(true);
  return 1;
  }

/*******************************************************************************/

// Backspace character
long FXText::onCmdBackspaceChar(FXObject*,FXSelector,void*){
  if(isEditable()){
    if(deletePendingSelection(true)) return 1;
    if(0<cursorpos){
      FXint pos=dec(cursorpos);
      removeText(pos,cursorpos-pos,true);
      moveCursor(pos,true);
      return 1;
      }
    }
  getApp()->beep();
  return 1;
  }


// Backspace word
long FXText::onCmdBackspaceWord(FXObject*,FXSelector,void*){
  if(isEditable()){
    if(deletePendingSelection(true)) return 1;
    FXint pos=leftWord(cursorpos);
    if(pos<cursorpos){
      removeText(pos,cursorpos-pos,true);
      moveCursor(pos,true);
      return 1;
      }
    }
  getApp()->beep();
  return 1;
  }


// Backspace bol
long FXText::onCmdBackspaceBol(FXObject*,FXSelector,void*){
  if(isEditable()){
    if(deletePendingSelection(true)) return 1;
    FXint pos=lineStart(cursorpos);
    if(pos<cursorpos){
      removeText(pos,cursorpos-pos,true);
      moveCursor(pos,true);
      return 1;
      }
    }
  getApp()->beep();
  return 1;
  }


// Delete character
long FXText::onCmdDeleteChar(FXObject*,FXSelector,void*){
  if(isEditable()){
    if(deletePendingSelection(true)) return 1;
    if(cursorpos<length){
      FXint pos=inc(cursorpos);
      removeText(cursorpos,pos-cursorpos,true);
      moveCursor(cursorpos,true);
      return 1;
      }
    }
  getApp()->beep();
  return 1;
  }


// Delete word
long FXText::onCmdDeleteWord(FXObject*,FXSelector,void*){
  if(isEditable()){
    if(deletePendingSelection(true)) return 1;
    FXint pos=rightWord(cursorpos);
    if(pos<length){
      removeText(cursorpos,pos-cursorpos,true);
      moveCursor(cursorpos,true);
      return 1;
      }
    }
  getApp()->beep();
  return 1;
  }


// Delete to end of line
long FXText::onCmdDeleteEol(FXObject*,FXSelector,void*){
  if(isEditable()){
    if(deletePendingSelection(true)) return 1;
    FXint pos=lineEnd(cursorpos);
    if(pos<length){
      removeText(cursorpos,pos-cursorpos,true);
      moveCursor(cursorpos,true);
      return 1;
      }
    }
  getApp()->beep();
  return 1;
  }


// Delete line
long FXText::onCmdDeleteLine(FXObject*,FXSelector,void*){
  if(isEditable()){
    FXint beg=lineStart(cursorpos);
    FXint end=nextLine(cursorpos);
    if(beg<end){
      removeText(beg,end-beg,true);
      moveCursor(beg,true);
      return 1;
      }
    }
  getApp()->beep();
  return 1;
  }


// Delete all text
long FXText::onCmdDeleteAll(FXObject*,FXSelector,void*){
  if(isEditable()){
    if(0<length){
      removeText(0,length,true);
      moveCursor(0,true);
      return 1;
      }
    }
  getApp()->beep();
  return 1;
  }

/*******************************************************************************/

// Shift selected lines left or right
long FXText::onCmdShiftText(FXObject*,FXSelector sel,void*){
  if(isEditable()){
    FXint start,end,len,amount;
    amount=0;
    switch(FXSELID(sel)){
      case ID_SHIFT_LEFT: amount=-1; break;
      case ID_SHIFT_RIGHT: amount=1; break;
      case ID_SHIFT_TABLEFT: amount=-tabcolumns; break;
      case ID_SHIFT_TABRIGHT: amount=tabcolumns; break;
      }
    if(selstartpos<selendpos){
      FXASSERT(0<=selstartpos && selstartpos<=length);
      FXASSERT(0<=selendpos && selendpos<=length);
      start=lineStart(selstartpos);
      end=selendpos;
      if(0<end && getByte(end-1)!='\n') end=nextLine(end);
      }
    else{
      start=lineStart(cursorpos);
      end=lineEnd(cursorpos);
      if(end<length) end++;
      }
    len=shiftText(start,end,amount,true);
    setAnchorPos(start);
    extendSelection(start+len,SelectChars,true);
    setCursorPos(start,true);
    modified=true;
    }
  else{
    getApp()->beep();
    }
  return 1;
  }


// Make selected text upper case
long FXText::onCmdChangeCase(FXObject*,FXSelector sel,void*){
  if(isEditable()){
    FXString text;
    FXint ss=selstartpos;
    FXint se=selendpos;
    extractText(text,ss,se-ss);
    if(FXSELID(sel)==ID_UPPER_CASE){
      text.upper();
      }
    else{
      text.lower();
      }
    replaceText(ss,se-ss,text,true);
    setSelection(ss,text.length(),true);
    setCursorPos(cursorpos,true);
    }
  else{
    getApp()->beep();
    }
  return 1;
  }


// Join lines
long FXText::onCmdJoinLines(FXObject*,FXSelector sel,void*){
  if(isEditable()){
    FXint pos=lineEnd(cursorpos);
    if(pos<length){
      removeText(pos,1,true);
      return 1;
      }
    }
  else{
    getApp()->beep();
    }
  return 1;
  }


// Goto start of enclosing block
long FXText::onCmdBlockBeg(FXObject*,FXSelector sel,void*){
  FXint what=FXSELID(sel)-ID_LEFT_BRACE;
  FXint beg=cursorpos-1;
  if(0<beg){
    if(getByte(beg)==lefthand[what]) beg--;
    FXint pos=matchBackward(beg,0,lefthand[what],righthand[what],1);
    if(0<=pos){
      moveCursor(pos+1,true);
      return 1;
      }
    }
  getApp()->beep();
  return 1;
  }


// Goto end of enclosing block
long FXText::onCmdBlockEnd(FXObject*,FXSelector sel,void*){
  FXint what=FXSELID(sel)-ID_RIGHT_BRACE;
  FXint start=cursorpos;
  if(start<length){
    if(getByte(start)==righthand[what]) start++;
    FXint pos=matchForward(start,length,lefthand[what],righthand[what],1);
    if(0<=pos){
      moveCursor(pos,true);
      return 1;
      }
    }
  getApp()->beep();
  return 1;
  }


// Goto matching character
long FXText::onCmdGotoMatching(FXObject*,FXSelector,void*){
  if(0<cursorpos){
    FXchar ch=getByte(cursorpos-1);
    FXint pos=findMatching(cursorpos-1,0,length,ch,1);
    if(0<=pos){
      moveCursor(pos+1,true);
      return 1;
      }
    }
  getApp()->beep();
  return 1;
  }


// Move cursor to indicated row
long FXText::onCmdCursorRow(FXObject* sender,FXSelector,void*){
  FXint row=cursorrow+1;
  sender->handle(this,FXSEL(SEL_COMMAND,ID_GETINTVALUE),(void*)&row);
  setCursorRow(row-1,true);
  return 1;
  }


// Being asked about current row number
long FXText::onUpdCursorRow(FXObject* sender,FXSelector,void*){
  FXint row=cursorrow+1;
  sender->handle(this,FXSEL(SEL_COMMAND,ID_SETINTVALUE),(void*)&row);
  return 1;
  }


// Move cursor to indicated column
long FXText::onCmdCursorColumn(FXObject* sender,FXSelector,void*){
  FXint col=cursorcol;
  sender->handle(this,FXSEL(SEL_COMMAND,ID_GETINTVALUE),(void*)&col);
  setCursorColumn(col,true);
  return 1;
  }


// Being asked about current column
long FXText::onUpdCursorColumn(FXObject* sender,FXSelector,void*){
  sender->handle(this,FXSEL(SEL_COMMAND,FXWindow::ID_SETINTVALUE),(void*)&cursorcol);
  return 1;
  }


// Editable toggle
long FXText::onCmdToggleEditable(FXObject*,FXSelector,void*){
  setEditable(!isEditable());
  return 1;
  }


// Update editable toggle
long FXText::onUpdToggleEditable(FXObject* sender,FXSelector,void*){
  sender->handle(this,isEditable()?FXSEL(SEL_COMMAND,ID_CHECK):FXSEL(SEL_COMMAND,ID_UNCHECK),NULL);
  sender->handle(this,FXSEL(SEL_COMMAND,ID_SHOW),NULL);
  sender->handle(this,FXSEL(SEL_COMMAND,ID_ENABLE),NULL);
  return 1;
  }


// Overstrike toggle
long FXText::onCmdToggleOverstrike(FXObject*,FXSelector,void*){
  setOverstrike(!isOverstrike());
  return 1;
  }


// Update overstrike toggle
long FXText::onUpdToggleOverstrike(FXObject* sender,FXSelector,void*){
  sender->handle(this,isOverstrike()?FXSEL(SEL_COMMAND,ID_CHECK):FXSEL(SEL_COMMAND,ID_UNCHECK),NULL);
  sender->handle(this,FXSEL(SEL_COMMAND,ID_SHOW),NULL);
  sender->handle(this,FXSEL(SEL_COMMAND,ID_ENABLE),NULL);
  return 1;
  }

/*******************************************************************************/

// Change top margin
void FXText::setMarginTop(FXint mt){
  if(margintop!=mt){
    margintop=mt;
    recalc();
    update();
    }
  }


// Change bottom margin
void FXText::setMarginBottom(FXint mb){
  if(marginbottom!=mb){
    marginbottom=mb;
    recalc();
    update();
    }
  }


// Change left margin
void FXText::setMarginLeft(FXint ml){
  if(marginleft!=ml){
    marginleft=ml;
    recalc();
    update();
    }
  }


// Change right margin
void FXText::setMarginRight(FXint mr){
  if(marginright!=mr){
    marginright=mr;
    recalc();
    update();
    }
  }


// Change the font
void FXText::setFont(FXFont* fnt){
  if(!fnt){ fxerror("%s::setFont: NULL font specified.\n",getClassName()); }
  if(font!=fnt){
    font=fnt;
    tabwidth=tabcolumns*font->getTextWidth(" ",1);
    barwidth=barcolumns*font->getTextWidth("8",1);
    if(getComposeContext()) getComposeContext()->setFont(font);
    recalc();
    update();
    }
  }


// Set wrap columns
void FXText::setWrapColumns(FXint cols){
  if(cols<=0) cols=1;
  if(cols!=wrapcolumns){
    wrapcolumns=cols;
    recalc();
    update();
    }
  }


// Set tab columns
void FXText::setTabColumns(FXint cols){
  cols=FXCLAMP(1,cols,MAXTABCOLUMNS);
  if(cols!=tabcolumns){
    tabcolumns=cols;
    tabwidth=tabcolumns*font->getTextWidth(" ",1);
    recalc();
    update();
    }
  }


// Change number of columns used for line numbers
void FXText::setBarColumns(FXint cols){
  if(cols<=0) cols=0;
  if(cols!=barcolumns){
    barcolumns=cols;
    barwidth=barcolumns*font->getTextWidth("8",1);
    recalc();
    update();
    }
  }


// Set text color
void FXText::setTextColor(FXColor clr){
  if(clr!=textColor){
    textColor=clr;
    update(barwidth,0,width-barwidth,height);
    }
  }


// Set select background color
void FXText::setSelBackColor(FXColor clr){
  if(clr!=selbackColor){
    selbackColor=clr;
    updateRange(selstartpos,selendpos);
    }
  }


// Set selected text color
void FXText::setSelTextColor(FXColor clr){
  if(clr!=seltextColor){
    seltextColor=clr;
    updateRange(selstartpos,selendpos);
    }
  }


// Change highlighted text color
void FXText::setHiliteTextColor(FXColor clr){
  if(clr!=hilitetextColor){
    hilitetextColor=clr;
    updateRange(hilitestartpos,hiliteendpos);
    }
  }


// Change highlighted background color
void FXText::setHiliteBackColor(FXColor clr){
  if(clr!=hilitebackColor){
    hilitebackColor=clr;
    updateRange(hilitestartpos,hiliteendpos);
    }
  }


// Change active background color
void FXText::setActiveBackColor(FXColor clr){
  if(clr!=activebackColor){
    activebackColor=clr;
    update(barwidth,0,width-barwidth,height);
    }
  }

// Change line number color
void FXText::setNumberColor(FXColor clr){
  if(clr!=numberColor){
    numberColor=clr;
    update(0,0,barwidth,height);
    }
  }


// Change bar color
void FXText::setBarColor(FXColor clr){
  if(clr!=barColor){
    barColor=clr;
    update(0,0,barwidth,height);
    }
  }


// Set cursor color
void FXText::setCursorColor(FXColor clr){
  if(clr!=cursorColor){
    cursorColor=clr;
    updateRange(cursorstartpos,cursorendpos);
    }
  }


// Change text style
void FXText::setTextStyle(FXuint style){
  FXuint opts=((style^options)&TEXT_MASK)^options;
  if(options!=opts){
    options=opts;
    recalc();
    update();
    }
  }


// Get text style
FXuint FXText::getTextStyle() const {
  return (options&TEXT_MASK);
  }


// Return true if editable
FXbool FXText::isEditable() const {
  return (options&TEXT_READONLY)==0;
  }


// Set widget is editable or not
void FXText::setEditable(FXbool edit){
  options^=((edit-1)^options)&TEXT_READONLY;
  }


// Return true if text is in overstrike mode
FXbool FXText::isOverstrike() const {
  return (options&TEXT_OVERSTRIKE)!=0;
  }


// Set overstrike mode
void FXText::setOverstrike(FXbool over){
  options^=((0-over)^options)&TEXT_OVERSTRIKE;
  }


// Set styled text mode
FXbool FXText::setStyled(FXbool styled){
  if(styled && !sbuffer){
    if(!callocElms(sbuffer,length+gapend-gapstart)) return false;
    update();
    }
  if(!styled && sbuffer){
    freeElms(sbuffer);
    update();
    }
  return true;
  }


// Set highlight styles
void FXText::setHiliteStyles(FXHiliteStyle* styles){
  hilitestyles=styles;
  update();
  }


// Change number of visible rows
void FXText::setVisibleRows(FXint rows){
  if(rows<0) rows=0;
  if(vrows!=rows){
    vrows=rows;
    recalc();
    }
  }


// Change number of visible columns
void FXText::setVisibleColumns(FXint cols){
  if(cols<0) cols=0;
  if(vcols!=cols){
    vcols=cols;
    recalc();
    }
  }


// Save object to stream
void FXText::save(FXStream& store) const {
  FXScrollArea::save(store);
  store << length;
  store.save(buffer,gapstart);
  store.save(buffer+gapend,length-gapstart);
  store << nvisrows;
  store.save(visrows,nvisrows+1);
  store << margintop;
  store << marginbottom;
  store << marginleft;
  store << marginright;
  store << wrapcolumns;
  store << tabcolumns;
  store << barcolumns;
  store << font;
  store << textColor;
  store << selbackColor;
  store << seltextColor;
  store << hilitebackColor;
  store << hilitetextColor;
  store << activebackColor;
  store << numberColor;
  store << cursorColor;
  store << barColor;
  store << vrows;
  store << vcols;
  store << help;
  store << tip;
  store << matchtime;
  }


// Load object from stream
void FXText::load(FXStream& store){
  FXScrollArea::load(store);
  store >> length;
  allocElms(buffer,length+MINSIZE);
  store.load(buffer,length);
  gapstart=length;
  gapend=length+MINSIZE;
  store >> nvisrows;
  allocElms(visrows,nvisrows+1);
  store.load(visrows,nvisrows+1);
  store >> margintop;
  store >> marginbottom;
  store >> marginleft;
  store >> marginright;
  store >> wrapcolumns;
  store >> tabcolumns;
  store >> barcolumns;
  store >> font;
  store >> textColor;
  store >> selbackColor;
  store >> seltextColor;
  store >> hilitebackColor;
  store >> hilitetextColor;
  store >> activebackColor;
  store >> numberColor;
  store >> cursorColor;
  store >> barColor;
  store >> vrows;
  store >> vcols;
  store >> help;
  store >> tip;
  store >> matchtime;
  }


// Clean up
FXText::~FXText(){
  getApp()->removeTimeout(this,ID_BLINK);
  getApp()->removeTimeout(this,ID_FLASH);
  freeElms(buffer);
  freeElms(sbuffer);
  freeElms(visrows);
  buffer=(FXchar*)-1L;
  sbuffer=(FXchar*)-1L;
  visrows=(FXint*)-1L;
  font=(FXFont*)-1L;
  hilitestyles=(FXHiliteStyle*)-1L;
  }

}
