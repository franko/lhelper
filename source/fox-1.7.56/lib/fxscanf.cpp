/********************************************************************************
*                                                                               *
*                   V a r a r g s   S c a n f   R o u t i n e s                 *
*                                                                               *
*********************************************************************************
* Copyright (C) 2002,2016 by Jeroen van der Zijp.   All Rights Reserved.        *
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
#include "fxascii.h"


/*
  Notes:
  - It may be not perfect, but at least its the same on all platforms.
  - Handles conversions of the form:

        % [*] [digits$] [width] [l|ll|h|hh|L|q|t|z] [n|p|d|u|i|x|X|o|D|c|s|[SET]|e|E|f|G|g|b]

  - Assignment suppression and number-grouping:
     '*'        When '*' is passed assignment of the matching quantity is suppressed.
     '''        Commas for thousands, like 1,000,000.

  - Positional argument:
     'digits$'  A sequence of decimal digits indication the position in the parameter
                list, followed by '$'.  The first parameter starts at 1.

  - Width:
     digits     Specifies field width to read, not counting spaces [except for %[] and
                %c and %n directives where spaces do count].

  - Interpretation of size parameters:

     'hh'       convert to FXchar
     'h'        convert to FXshort
     ''         convert to FXint (or FXfloat if real)
     'l'        convert to long (or FXdouble if real)
     'll'       convert to FXlong (64-bit number)
     'L'        ditto
     'q'        ditto
     't'        convert to FXival (size depends on pointer size)
     'z'        ditto

  - Conversion specifiers:

     'd'        Decimal integer conversion.
     'b'        Binary integer conversion.
     'i'        Integer conversion from octal, hex, or decimal number.
     'o'        Octal integer conversion.
     'u'        Unsigned decimal integer conversion.
     'x' or 'X' Hexadecimal conversion.
     'c'        String conversion.
     's'        String conversion of printing characters [no spaces].
     'n'        Assign number of characters scanned so far.
     'p'        Hexadecimal pointer conversion.
     [SET]      String conversion of characters in set only.
     'e', 'E',  Floating point conversion.
     'f', 'F'   Floating point conversion.
     'g', 'G'   Floating point conversion.


  - We can print comma's like 1,000,000.00 but we can't read them...
*/

#ifdef WIN32
#ifndef va_copy
#define va_copy(arg,list) ((arg)=(list))
#endif
#endif

#define MAXDIGS  20     // Maximum number of significant digits

/*******************************************************************************/

using namespace FX;

namespace FX {


// Declarations
extern FXAPI FXint __sscanf(const FXchar* string,const FXchar* format,...);
extern FXAPI FXint __vsscanf(const FXchar* string,const FXchar* format,va_list arg_ptr);


// Type modifiers
enum {
  ARG_HALFHALF,         // 'hh'
  ARG_HALF,             // 'h'
  ARG_DEFAULT,          // (No specifier)
  ARG_LONG,             // 'l'
  ARG_LONGLONG,         // 'll' / 'L' / 'q'
  ARG_VARIABLE          // Depending on size of pointer
  };

/*******************************************************************************/

static const FXchar* grouping(const FXchar* begin,const FXchar* end){
  while(end>begin){
    const FXchar* cp=end-1;
    const FXchar* new_end;
    const FXchar* group_end;

    // Scan backwards for thousands separator
    while(cp>=begin){   
      if(*cp==',') break;
      --cp;
      }

    // No numbers grouping
    if(cp<begin) return end;

    // Three digits following a ','
    if(end-cp==3+1){

      // No more in front
      if(cp<begin) return end;

      // Loop while the grouping is correct
      new_end=cp-1;
      while(1){

        // Scan backwards for next thousands separator
        group_end=--cp;
        while(cp>=begin){
          if(*cp==',') break;
          --cp;
          }

        // Found correct start
        if(cp<begin && group_end-cp<=3) return end;

        // Incorrect group; bail
        if(cp<begin || group_end-cp!=3) break;
        }

      // Drop incorrect tail
      end=new_end;
      }
    else{
      if(end-cp>3+1) end=cp+3+1;        // Even the first group was wrong; determine maximum shift
      else if(cp<begin) return end;     // This number does not fill the first group, but is correct
      else end=cp;                      // CP points to a thousands separator character
      }
    }
  return FXMAX(begin,end);
  }


// Scan with va_list arguments
FXint __vsscanf(const FXchar* string,const FXchar* format,va_list args){
  register FXint modifier,width,convert,comma,base,digits,count,exponent,expo,neg,nex,pos,ch,nn,v;
  register const FXchar *start=string;
  register const FXchar *ss;
  register FXchar *ptr;
  FXdouble number;
  FXdouble mult;
  FXulong  value;
  FXchar   set[256];
  va_list ag;

  count=0;

  FXTRACE((1,"string=%s segment=%.*s\n",string,(int)(grouping(string,string+strlen(string))-string),string));

  // Process format string
  va_copy(ag,args);
  while((ch=*format++)!='\0'){

    // Check for format-characters
    if(ch=='%'){

      // Get next format character
      ch=*format++;

      // Check for '%%'
      if(ch=='%') goto nml;

      // Default settings
      modifier=ARG_DEFAULT;
      width=0;
      convert=1;
      comma=0;
      base=0;
      pos=-1;

      // Parse format specifier
flg:  switch(ch){
        case '*':                                       // Suppress conversion
          convert=0;
          ch=*format++;
          goto flg;
        case '\'':                                      // Print thousandths
          comma=',';                                    // Thousands grouping character
          ch=*format++;
          goto flg;
        case '0':                                       // Width or positional parameter
        case '1':
        case '2':
        case '3':
        case '4':
        case '5':
        case '6':
        case '7':
        case '8':
        case '9':
          width=ch-'0';
          ch=*format++;
          while(Ascii::isDigit(ch)){
            width=width*10+ch-'0';
            ch=*format++;
            }
          if(ch=='$'){                                  // Positional parameter
            ch=*format++;
            if(width<=0) goto x;                        // Not a legal parameter position
            va_copy(ag,args);
            for(pos=1; pos<width; ++pos){               // Advance to position prior to arg
              (void)va_arg(ag,void*);
              }
            width=0;                                    // Reset width
            }
          goto flg;
        case 'l':                                       // Long
          modifier=ARG_LONG;
          ch=*format++;
          if(ch=='l'){                                  // Long Long
            modifier=ARG_LONGLONG;
            ch=*format++;
            }
          goto flg;
        case 'h':                                       // Short
          modifier=ARG_HALF;
          ch=*format++;
          if(ch=='h'){                                  // Char
            modifier=ARG_HALFHALF;
            ch=*format++;
            }
          goto flg;
        case 'L':                                       // Long Long
        case 'q':
          modifier=ARG_LONGLONG;
          ch=*format++;
          goto flg;
        case 't':                                       // Size depends on pointer
        case 'z':
          modifier=ARG_VARIABLE;
          ch=*format++;
          goto flg;
        case 'n':                                       // Consumed characters till here
          value=string-start;
          if(convert){
            if(modifier==ARG_DEFAULT){                  // 32-bit always
              *va_arg(ag,FXint*)=(FXint)value;
              }
            else if(modifier==ARG_LONG){                // Whatever size a long is
              *va_arg(ag,long*)=(long)value;
              }
            else if(modifier==ARG_LONGLONG){            // 64-bit always
              *va_arg(ag,FXlong*)=value;
              }
            else if(modifier==ARG_HALF){                // 16-bit always
              *va_arg(ag,FXshort*)=(FXshort)value;
              }
            else if(modifier==ARG_HALFHALF){            // 8-bit always
              *va_arg(ag,FXchar*)=(FXchar)value;
              }
            else{                                       // Whatever size a pointer is
              *va_arg(ag,FXival*)=(FXival)value;
              }
            }
          break;
        case 'D':
          modifier=ARG_LONG;
          base=10;
          goto integer;
        case 'p':                                       // Hex pointer
          modifier=ARG_VARIABLE;
          base=16;
          comma=0;
          goto integer;
        case 'x':                                       // Hex
        case 'X':
          base=16;
          comma=0;
          goto integer;
        case 'o':                                       // Octal
          base=8;
          comma=0;
          goto integer;
        case 'b':                                       // Binary
          base=2;
          comma=0;
          goto integer;
        case 'd':                                       // Decimal
        case 'u':
          base=10;
        case 'i':                                       // Either
integer:  value=0;
          digits=0;
          if(width<1) width=2147483647;                 // Width at least 1
          while(Ascii::isSpace(*string)) string++;      // Skip white space; not included in field width
          if((neg=(*string=='-')) || (*string=='+')){   // Handle sign
            string++;
            width--;
            }
          if(0<width && *string=='0'){                          // Got a '0'
            digits++;
            string++;
            width--;
            if(0<width && (*string=='x' || *string=='X')){      // Got a '0x'
              if(base==0){ comma=0; base=16; }                  // If not set yet, '0x' means set base to 16
              if(base==16){                                     // But don't eat the 'x' if base wasn't 16!
                string++;
                width--;
                }
              }
            else if(0<width && (*string=='b' || *string=='B')){ // Got a '0b'
              if(base==0){ comma=0; base=2; }                   // If not set yet, '0b' means set base to 2
              if(base==2){                                      // But don't eat the 'b' if base wasn't 2!
                string++;
                width--;
                }
              }
            else{
              if(base==0){ comma=0; base=8; }                   // If not set yet, '0' means set base to 8
              }
            }
          else{
            if(base==0){ base=10; }                             // Not starting with '0' or '0x', so its decimal
            }
/*
          if(0<width && *string && *string==comma){             // Thousands grouping
            width--;
            string++;
            }
*/
          while(0<width && 0<=(v=Ascii::digitValue(*string)) && v<base){        // Convert to integer
            value=value*base+v;
            digits++;
            string++;
            width--;
            }
          if(!digits) goto x;                                   // No digits seen!
          if(neg){                                              // Apply sign
            value=0-value;
            }
          if(convert){
            if(modifier==ARG_DEFAULT){                          // 32-bit always
              *va_arg(ag,FXint*)=(FXint)value;
              }
            else if(modifier==ARG_LONG){                        // Whatever size a long is
              *va_arg(ag,long*)=(long)value;
              }
            else if(modifier==ARG_LONGLONG){                    // 64-bit always
              *va_arg(ag,FXlong*)=value;
              }
            else if(modifier==ARG_HALF){                        // 16-bit always
              *va_arg(ag,FXshort*)=(FXshort)value;
              }
            else if(modifier==ARG_HALFHALF){                    // 8-bit always
              *va_arg(ag,FXchar*)=(FXchar)value;
              }
            else{                                               // Whatever size a pointer is
              *va_arg(ag,FXival*)=(FXival)value;
              }
            count++;
            }
          break;
        case 'e':                                       // Floating point
        case 'E':
        case 'f':
        case 'F':
        case 'g':
        case 'G':
          number=0.0;
          mult=1.0;
          exponent=-1;
          digits=0;
          if(width<1) width=2147483647;                         // Width at least 1
          while(Ascii::isSpace(*string)) string++;              // Skip white space; not included in field width
          if((neg=(*string=='-')) || (*string=='+')){           // Handle sign
            string++;
            width--;
            }
          if(width<=0 || !(*string=='.' || ('0'<=*string && *string<='9'))) goto x;     // Bail if not starting a number now
          while(0<width && *string=='0'){                       // Leading zeros
            string++;
            width--;
            }
          while(0<width && '0'<=*string && *string<='9'){       // Mantissa digits
            if(digits<MAXDIGS){
              number+=(*string-'0')*mult;
              mult*=0.1;
              }
            exponent++;
            digits++;
            string++;
            width--;
            }
          if(0<width && *string=='.'){                          // Mantissa decimals following '.'
            string++;
            width--;
            while(0<width && '0'<=*string && *string<='9'){
              if(digits<MAXDIGS){
                number+=(*string-'0')*mult;
                mult*=0.1;
                }
              digits++;
              string++;
              width--;
              }
            }
          if(1<width && (*string|0x20)=='e'){                   // Handle exponent, tentatively
            ss=string;
            ss++;
            width--;
            expo=0;
            if((nex=(*ss=='-')) || (*ss=='+')){                 // Handle exponent sign
              ss++;
              width--;
              }
            if(0<width && '0'<=*ss && *ss<='9'){                // Have exponent?
              while(0<width && '0'<=*ss && *ss<='9'){
                expo=expo*10+(*ss-'0');
                ss++;
                width--;
                }
              if(nex){
                exponent-=expo;
                }
              else{
                exponent+=expo;
                }
              string=ss;                                        // Eat exponent characters
              }
            }
          if(number!=0.0){
            if(308<=exponent){                                  // Check for overflow
              if((308<exponent) || (1.79769313486231570815<=number)){
                number=1.79769313486231570815E+308;
                exponent=0;
                }
              }
            if(exponent<-308){                                  // Check for denormal or underflow
              if((exponent<-324) || ((exponent==-324) && (number<=4.94065645841246544177))){
                number=0.0;
                exponent=0;
                }
              number*=1.0E-16;
              exponent+=16;
              }
            number*=Math::ipow(10.0,exponent);                  // In range
            if(neg){                                            // Apply sign
              number=-number;
              }
            }
          if(convert){
            if(modifier==ARG_DEFAULT){
              *va_arg(ag,FXfloat*)=(FXfloat)number;             // 32-bit float
              }
            else{
              *va_arg(ag,FXdouble*)=number;                     // 64-bit double
              }
            count++;
            }
          break;
        case 'c':                                       // Character(s)
          if(width<1) width=1;                          // Width at least 1
          if(convert){
            ptr=va_arg(ag,FXchar*);
            while(0<width && *string){
              *ptr++=*string++;
              width--;
              }
            count++;
            }
          else{
            while(0<width && *string){
              string++;
              width--;
              }
            }
          break;
        case 's':                                       // String
          if(width<1) width=2147483647;                 // Width at least 1
          while(Ascii::isSpace(*string)) string++;      // Skip white space
          if(convert){
            ptr=va_arg(ag,FXchar*);
            while(0<width && *string && !Ascii::isSpace(*string)){
              *ptr++=*string++;
              width--;
              }
            *ptr='\0';
            count++;
            }
          else{
            while(0<width && *string && !Ascii::isSpace(*string)){
              string++;
              width--;
              }
            }
          break;
        case '[':                                       // Character set
          if(width<1) width=2147483647;                 // Width at least 1
          ch=(FXuchar)*format++;
          v=1;                                          // Add characters to set
          if(ch=='^'){                                  // Negated character set
            ch=(FXuchar)*format++;
            v=0;                                        // Remove characters from set
            }
          memset(set,1-v,sizeof(set));                  // Initialize set
          if(ch=='\0') goto x;                          // Format error
          for(;;){                                      // Parse set
            set[ch]=v;
            nn=(FXuchar)*format++;
            if(nn=='\0') goto x;                        // Format error
            if(nn==']') break;
            if(nn=='-'){
              nn=(FXuchar)*format;
              if(nn!=']' && ch<=nn){                    // Range if not at end
                while(ch<nn){ set[++ch]=v; }
                format++;
                }
              else{                                     // Otherwise just '-'
                nn='-';
                }
              }
            ch=nn;
            }
          if(convert){
            ptr=va_arg(ag,FXchar*);
            while(0<width && *string && set[(FXuchar)*string]){
              *ptr++=*string++;
              width--;
              }
            *ptr='\0';
            count++;
            }
          else{
            while(0<width && *string && set[(FXuchar)*string]){
              string++;
              width--;
              }
            }
          break;
        default:                                        // Format error
          goto x;
        }
      continue;
      }

    // Check for spaces
nml:if(Ascii::isSpace(ch)){
      while(Ascii::isSpace(*format)) format++;
      while(Ascii::isSpace(*string)) string++;
      continue;
      }

    // Regular characters must match
    if(*string!=ch) break;

    // Next regular character
    string++;
    }
x:va_end(ag);
  return count;
  }


// Scan with variable number of arguments
FXint __sscanf(const FXchar* string,const FXchar* format,...){
  va_list args;
  va_start(args,format);
  FXint result=__vsscanf(string,format,args);
  va_end(args);
  return result;
  }

}
