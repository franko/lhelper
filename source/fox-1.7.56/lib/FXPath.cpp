/********************************************************************************
*                                                                               *
*                  P a t h   N a m e   M a n i p u l a t i o n                  *
*                                                                               *
*********************************************************************************
* Copyright (C) 2000,2016 by Jeroen van der Zijp.   All Rights Reserved.        *
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
#include "fxascii.h"
#include "fxunicode.h"
#include "FXArray.h"
#include "FXHash.h"
#include "FXStream.h"
#include "FXString.h"
#include "FXPath.h"
#include "FXSystem.h"
#include "FXStat.h"
#include "FXFile.h"
#include "FXDir.h"
#if defined(WIN32)
#include <shellapi.h>
#endif



/*
  Notes:

  - Windows 95 and NT:
      -  1 to 255 character name.
      -  Complete path for a file or project name cannot exceed 259
         characters, including the separators.
      -  May not begin or end with a space.
      -  May not begin with a $
      -  May contain 1 or more file extensions (eg. MyFile.Ext1.Ext2.Ext3.Txt).
      -  Legal characters in the range of 32 - 255 but not ?"/\<>*|:
      -  Filenames may be mixed case.
      -  Filename comparisons are case insensitive (eg. ThIs.TXT = this.txt).

  - MS-DOS and Windows 3.1:
      -  1 to 11 characters in the 8.3 naming convention.
      -  Legal characters are A-Z, 0-9, Double Byte Character Set (DBCS)
         characters (128 - 255), and _^$~!#%&-{}@'()
      -  May not contain spaces, 0 - 31, and "/\[]:;|=,
      -  Must not begin with $
      -  Uppercase only filename.

  - Deal with Windows paths "\\?\" long pathname convention.
*/


using namespace FX;

/*******************************************************************************/

namespace FX {


// Return root of given path, including share name or drive letter
FXString FXPath::root(const FXString& file){
  if(!file.empty()){
#if defined(WIN32)
    FXString result(file);
    FXint p=0,q=0;
    if(ISPATHSEP(result[q])){                                   // UNC
      result[p++]=PATHSEP; q++;
      if(ISPATHSEP(result[q])){
        result[p++]=PATHSEP; q++;
        while(ISPATHSEP(result[q])) q++;
        while(result[q]){
          if(ISPATHSEP(result[q])){ result[p++]=PATHSEP; break; }
          result[p++]=result[q++];
          }
        }
      return result.trunc(p);
      }
    if(Ascii::isLetter(result[q]) && result[q+1]==':'){         // C:
      result[p++]=result[q++]; result[p++]=':'; q++;
      if(ISPATHSEP(result[q])){
        result[p++]=PATHSEP;
        }
      return result.trunc(p);
      }
#else
    if(ISPATHSEP(file[0])){
      return PATHSEPSTRING;
      }
#endif
    }
  return FXString::null;
  }


// Return share name from Windows UNC filename
FXString FXPath::share(const FXString& file){
#if defined(WIN32)
  if(!file.empty()){
    FXint f,n;
    if(ISPATHSEP(file[0])){                                   // UNC
      if(ISPATHSEP(file[1])){
        n=2;
        while(ISPATHSEP(file[n])) n++;
        f=n;
        while(file[n]){
          if(ISPATHSEP(file[n])) break;
          n++;
          }
        return FXString(&file[f],n-f);
        }
      }
    }
#endif
  return FXString::null;
  }


// Return directory part of pathname, assuming full pathname.
// Note that directory("/bla/bla/") is "/bla/bla" and NOT "/bla".
// However, directory("/bla/bla") is "/bla" as we expect!
FXString FXPath::directory(const FXString& file){
  if(!file.empty()){
    FXString result(file);
    FXint p=0,q=0,s;
#if defined(WIN32)
    if(ISPATHSEP(result[q])){                                   // UNC
      result[p++]=PATHSEP; q++;
      if(ISPATHSEP(result[q])){
        result[p++]=PATHSEP; q++;
        while(ISPATHSEP(result[q])) q++;
        }
      }
    else if(Ascii::isLetter(result[q]) && result[q+1]==':'){    // C:
      result[p++]=result[q++]; result[p++]=':'; q++;
      if(ISPATHSEP(result[q])){
        result[p++]=PATHSEP; q++;
        while(ISPATHSEP(result[q])) q++;
        }
      }
#else
    if(ISPATHSEP(result[q])){
      result[p++]=PATHSEP; q++;
      while(ISPATHSEP(result[q])) q++;
      }
#endif
    s=p;
    while(result[q]){
      if(ISPATHSEP(result[q])){
        result[s=p++]=PATHSEP;
        while(ISPATHSEP(result[q])) q++;
        continue;
        }
      result[p++]=result[q++];
      }
    return result.trunc(s);
    }
  return FXString::null;
  }


// Return name and extension part of pathname.
// Note that name("/bla/bla/") is "" and NOT "bla".
// However, name("/bla/bla") is "bla" as we expect!
FXString FXPath::name(const FXString& file){
  if(!file.empty()){
    FXint n=0,f;
#if defined(WIN32)
    if(Ascii::isLetter(file[0]) && file[1]==':') n=2;
#endif
    f=n;
    while(file[n]){
      if(ISPATHSEP(file[n])) f=n+1;
      n++;
      }
    return FXString(&file[f],n-f);
    }
  return FXString::null;
  }


// Return file title, i.e. document name only:
//
//  /path/aa        -> aa
//  /path/aa.bb     -> aa
//  /path/aa.bb.cc  -> aa.bb
//  /path/.aa       -> .aa
FXString FXPath::title(const FXString& file){
  if(!file.empty()){
    FXint i=0,f,e,b;
#if defined(WIN32)
    if(Ascii::isLetter(file[0]) && file[1]==':') i=2;
#endif
    f=i;
    while(file[i]){
      if(ISPATHSEP(file[i])) f=i+1;
      i++;
      }
    b=f;
    if(file[b]=='.') b++;     // Leading '.'
    e=i;
    while(b<i){
      if(file[--i]=='.'){ e=i; break; }
      }
    return FXString(&file[f],e-f);
    }
  return FXString::null;
  }


// Return extension, if there is one:
//
//  /path/aa        -> ""
//  /path/aa.bb     -> bb
//  /path/aa.bb.cc  -> cc
//  /path/.aa       -> ""
FXString FXPath::extension(const FXString& file){
  if(!file.empty()){
    FXint n=0,f,e,i;
#if defined(WIN32)
    if(Ascii::isLetter(file[0]) && file[1]==':') n=2;
#endif
    f=n;
    while(file[n]){
      if(ISPATHSEP(file[n])) f=n+1;
      n++;
      }
    if(file[f]=='.') f++;     // Leading '.'
    e=i=n;
    while(f<i){
      if(file[--i]=='.'){ e=i+1; break; }
      }
    return FXString(&file[e],n-e);
    }
  return FXString::null;
  }


// Return file name less the extension
//
//  /path/aa        -> /path/aa
//  /path/aa.bb     -> /path/aa
//  /path/aa.bb.cc  -> /path/aa.bb
//  /path/.aa       -> /path/.aa
FXString FXPath::stripExtension(const FXString& file){
  if(!file.empty()){
    FXString result(file);
    FXint p=0,q=0,s,e;
#if defined(WIN32)
    if(ISPATHSEP(result[q])){                                   // UNC
      result[p++]=PATHSEP; q++;
      if(ISPATHSEP(result[q])){
        result[p++]=PATHSEP; q++;
        while(ISPATHSEP(result[q])) q++;
        }
      }
    else if(Ascii::isLetter(result[q]) && result[q+1]==':'){    // C:
      result[p++]=result[q++];
      result[p++]=':'; q++;
      if(ISPATHSEP(result[q])){
        result[p++]=PATHSEP; q++;
        while(ISPATHSEP(result[q])) q++;
        }
      }
#else
    if(ISPATHSEP(result[q])){
      result[p++]=PATHSEP; q++;
      while(ISPATHSEP(result[q])) q++;
      }
#endif
    s=p;
    while(result[q]){
      if(ISPATHSEP(result[q])){
        result[p++]=PATHSEP; s=p;
        while(ISPATHSEP(result[q])) q++;
        continue;
        }
      result[p++]=result[q++];
      }
    if(result[s]=='.') s++;     // Leading '.'
    e=p;
    while(s<p){
      if(result[--p]=='.'){ e=p; break; }
      }
    return result.trunc(e);
    }
  return FXString::null;
  }


#if defined(WIN32)

// Return drive letter prefix "c:"
FXString FXPath::drive(const FXString& file){
  if(Ascii::isLetter(file[0]) && file[1]==':'){
    FXchar buffer[3]={Ascii::toLower(file[0]),':','\0'};
    return FXString(buffer,2);
    }
  return FXString::null;
  }

#else

// Return drive letter prefix "c:"
FXString FXPath::drive(const FXString&){
  return FXString::null;
  }

#endif


// Perform tilde or environment variable expansion
FXString FXPath::expand(const FXString& file){
  if(!file.empty()){
    FXString result;
#if defined(WIN32)
    FXString var,val;
    FXint b=0,e;
    while(file[b]){
      if(file[b]=='%'){
        e=file.find('%',b+1);
        if(b<e){
          var=file.mid(b+1,e-b-1);
          val=FXSystem::getEnvironment(var);
          if(!val.empty()){                             // Value found, replace the %VARIABLE% with it
            result.append(val);
            }
          else{                                         // No value; leave %VARIABLE% in place
            result.append(&file[b],e-b+1);
            }
          b=e+1;
          }
        else{                                           // Unmatched '%'; just copy the rest
          result.append(&file[b],file.length()-b);
          b=file.length();
          }
        }
      else{
        e=file.find('%',b+1);
        if(b<e){
          result.append(&file[b],e-b);                  // Copy string up till first '%'
          b=e;
          }
        else{
          result.append(&file[b],file.length()-b);      // Just copy the rest
          b=file.length();
          }
        }
      }
#else
    FXint b,e,n;

    // Expand leading tilde of the form ~/filename or ~user/filename
    n=0;
    if(file[n]=='~'){
      n++;
      b=n;
      while(file[n] && !ISPATHSEP(file[n])) n++;
      e=n;
      result.append(FXSystem::getUserDirectory(file.mid(b,e-b)));
      }

    // Expand environment variables of the form $HOME or ${HOME}
    while(file[n]){
      if(file[n]=='$'){
        n++;
        if(file[n]=='{') n++;
        b=n;
        while(Ascii::isAlphaNumeric(file[n]) || file[n]=='_') n++;
        e=n;
        if(file[n]=='}') n++;
        result.append(FXSystem::getEnvironment(file.mid(b,e-b)));
        continue;
        }
      result.append(file[n]);
      n++;
      }
#endif
    return result;
    }
  return FXString::null;
  }


// Contract path based on environment variables
//
//      /home/jeroen/junk
//      /home/someoneelse/junk
//      /usr/local/ACE_wrappers/TAO
//
//    to:
//
//      ~/junk
//      ~someoneelse/junk
//      $ACE_ROOT/TAO
//
FXString FXPath::contract(const FXString& file,const FXString& user,const FXString& var){
  FXString result(file);
  if(!result.empty()){
    FXString val;
    FXint pos;
    if(FXPath::isAbsolute(result)){
      val=FXSystem::getUserDirectory(user);
      if(!val.empty()){
#if defined(WIN32)
        if(comparecase(result,val,val.length())==0 && ((result.length()==val.length()) || ISPATHSEP(result[val.length()]))){
          result.replace(0,val.length(),"~"+user);
          }
#else
        if(compare(result,val,val.length())==0 && ((result.length()==val.length()) || ISPATHSEP(result[val.length()]))){
          result.replace(0,val.length(),"~"+user);
          }
#endif
        }
      }
    val=FXSystem::getEnvironment(var);
    if(!val.empty()){
      if(0<=(pos=result.find(val))){
        if((pos==0 || ISPATHSEP(result[pos-1])) && (pos+val.length()==result.length() || ISPATHSEP(result[pos+val.length()]))){
          result.replace(pos,val.length(),"$"+var);
          }
        }
      }
    }
  return result;
  }


// Simplify a file path; the path will remain relative if it was relative,
// or absolute if it was absolute.  Also, a trailing "/" will be preserved
// as this is important in other functions.
//
// Examples:
//
//  /aa/bb/../cc     -> /aa/cc
//  /aa/bb/../cc/    -> /aa/cc/
//  /aa/bb/../..     -> /
//  ../../bb         -> ../../bb
//  ../../bb/        -> ../../bb/
//  /../             -> /
//  ./aa/bb/../../   -> ./
//  a/..             -> .
//  a/../            -> ./
//  ./a              -> ./a
//  /////./././      -> /
//  c:/../           -> c:/
//  c:a/..           -> c:
//  /.               -> /
//  /a/b/./          -> /a/b/
//  /a/b/.           -> /a/b
//  /aa/ccc.../../bb -> /aa/bb
FXString FXPath::simplify(const FXString& file){
  if(!file.empty()){
    FXString result(file);
    FXint p=0,q=0,s;
#if defined(WIN32)
    if(ISPATHSEP(result[q])){                                   // UNC
      result[p++]=PATHSEP; q++;
      if(ISPATHSEP(result[q])){
        result[p++]=PATHSEP; q++;
        while(ISPATHSEP(result[q])) q++;
        }
      }
    else if(Ascii::isLetter(result[q]) && result[q+1]==':'){    // C:
      result[p++]=result[q++];
      result[p++]=':'; q++;
      if(ISPATHSEP(result[q])){
        result[p++]=PATHSEP; q++;
        while(ISPATHSEP(result[q])) q++;
        }
      }
#else
    if(ISPATHSEP(result[q])){
      result[p++]=PATHSEP; q++;
      while(ISPATHSEP(result[q])) q++;
      }
#endif
    s=p;
    while(result[q]){
      while(result[q] && !ISPATHSEP(result[q])){
        result[p++]=result[q++];
        }
      if(ISPATHSEP(result[q])){
        result[p++]=PATHSEP; q++;
        while(ISPATHSEP(result[q])) q++;
        }
      if(2<=p && ISPATHSEP(result[p-2]) && result[p-1]=='.'){   // Case "xxx/."
        p--;
        if(s<p) p--;
        }
      else if(3<=p && ISPATHSEP(result[p-3]) && result[p-2]=='.' && ISPATHSEP(result[p-1])){    // Case "xxx/./"
        p-=2;
        }
      else if(3<=p && ISPATHSEP(result[p-3]) && result[p-2]=='.' && result[p-1]=='.' && !(((6<=p && ISPATHSEP(result[p-6])) || 5==p) && result[p-5]=='.' && result[p-4]=='.')){ // Case "xxx/.."
        p-=2;
        if(s<p){                // Pathological case "/.." will become "/"
          p--;
          while(s<p && !ISPATHSEP(result[p-1])) p--;
          if(s<p && ISPATHSEP(result[p-1])) p--;
          if(p==0){                             // Don't allow empty path
            result[p++]='.';
            }
          }
        }
      else if(4<=p && ISPATHSEP(result[p-4]) && result[p-3]=='.' && result[p-2]=='.' && ISPATHSEP(result[p-1]) && !(((7<=p && ISPATHSEP(result[p-7])) || 6==p) && result[p-6]=='.' && result[p-5]=='.')){       // Case "xxx/../"
        p-=3;
        if(s<p){                // Pathological case "/../" will become "/"
          p--;
          while(s<p && !ISPATHSEP(result[p-1])) p--;
          if(p==0){                             // Don't allow empty path
            result[p++]='.';
            result[p++]=PATHSEP;                // Keep trailing "/" around
            }
          }
        }
      }
    return result.trunc(p);
    }
  return FXString::null;
  }


// Build absolute pathname
FXString FXPath::absolute(const FXString& file){
#if defined(WIN32)
  if(!((ISPATHSEP(file[0]) && ISPATHSEP(file[1])) || (Ascii::isLetter(file[0]) && file[1]==':' && ISPATHSEP(file[2])))){
    if(ISPATHSEP(file[0])){
      return FXPath::simplify(FXSystem::getCurrentDrive()+file);        // \file -> D:\file
      }
    if(Ascii::isLetter(file[0]) && file[1]==':'){
      return FXPath::simplify(file.left(2)+PATHSEPSTRING+file.right(file.length()-2));  // D:file -> D:\file
      }
    FXString result(FXSystem::getCurrentDirectory());
    if(!file.empty()){
      if(!ISPATHSEP(result.tail())) result.append(PATHSEP);
      result.append(file);
      }
    return FXPath::simplify(result);                                    // file -> D:\cwd\file
    }
  return FXPath::simplify(file);                                        // D:\dirs\file  OR  \\share\file
#else
  if(!ISPATHSEP(file[0])){
    FXString result(FXSystem::getCurrentDirectory());
    if(!file.empty()){
      if(!ISPATHSEP(result.tail())) result.append(PATHSEP);
      result.append(file);
      }
    return FXPath::simplify(result);                                    // file -> /cwd/file
    }
  return FXPath::simplify(file);                                        // /dirs/file
#endif
  }


// Build absolute pathname from parts
FXString FXPath::absolute(const FXString& base,const FXString& file){
#if defined(WIN32)
  if(!((ISPATHSEP(file[0]) && ISPATHSEP(file[1])) || (Ascii::isLetter(file[0]) && file[1]==':' && ISPATHSEP(file[2])))){
    if(ISPATHSEP(file[0])){
      return FXPath::simplify(FXSystem::getCurrentDrive()+file);        // \file -> D:\file
      }
    if(Ascii::isLetter(file[0]) && file[1]==':'){
      return FXPath::simplify(file.left(2)+PATHSEPSTRING+file.right(file.length()-2));  // D:file -> D:\file
      }
    FXString result(FXPath::absolute(base));
    if(!file.empty()){
      if(!ISPATHSEP(result.tail())) result.append(PATHSEP);
      result.append(file);
      }
    return FXPath::simplify(result);                                    // file -> /base/file
    }
  return FXPath::simplify(file);                                        // D:\dirs\file  OR  \\share\file
#else
  if(!ISPATHSEP(file[0])){
    FXString result(FXPath::absolute(base));
    if(!file.empty()){
      if(!ISPATHSEP(result.tail())) result.append(PATHSEP);
      result.append(file);
      }
    return FXPath::simplify(result);                                    // file -> /base/file
    }
  return FXPath::simplify(file);                                        // /dirs/file
#endif
  }


// Return relative path of file to given absolute base directory
//
// Examples:
//
//  Base       File         Result      Comment
//  a          /b           /b          Base is relative but file is not
//  /a         b            b           Base is absolute but file is not
//
//  /a/b/c     /a/b/c/d     d           Branch point is /a/b/c
//  /a/b/c/    /a/b/c/d     d           Branch point is /a/b/c
//
//  a          b            ../b        Branch point is assumed ..
//  ./a        ./b          ../b        Branch point is assumed ..
//
//  /a/b/c     /a/b/c       .           Equal
//  /a/b/c/    /a/b/c/      .           Equal
//  /a/b/c     /a/b/c/      .           Equal
//  /a/b/c/    /a/b/c       .           Equal
//
//  ../a/b/c   ../a/b/c/d   d           Branch point is ../a/b/c
//
//  /a/b/c/d   /a/b/c       ../         Branch point is /a/b/c
//
//  /a/b/c/d   /a/b/q       ../../q     Branch point is /a/b
//
//  /          /a           a           Branch point is /
//  /a         /b           ../b        Branch point is /
//  /a/b       /c           ../../c     Branch point is /
//  /          /a/b         a/b         Branch point is /
//  /p/q       /a/b         ../../a/b   Branch point is /
//
FXString FXPath::relative(const FXString& base,const FXString& file){

  // Base and file non-empty and either both absolute, or both relative
  if(!base.empty() && !file.empty() && (FXPath::isAbsolute(base) == FXPath::isAbsolute(file))){
    FXint p=0,q=0,bp=0,bq=0;

    // Find branch point
#if defined(WIN32)
    while(base[p] && file[q]){
      if(ISPATHSEP(base[p]) && ISPATHSEP(file[q])){
        bp=p; while(ISPATHSEP(base[p])) p++;    // Eat multiple slashes
        bq=q; while(ISPATHSEP(file[q])) q++;
        continue;
        }
      if(Ascii::toLower(base[p])==Ascii::toLower(file[q])){
        p++;
        q++;
        continue;
        }
      break;
      }
#else
    while(base[p] && file[q]){
      if(ISPATHSEP(base[p]) && ISPATHSEP(file[q])){
        bp=p; while(ISPATHSEP(base[p])) p++;    // Eat multiple slashes
        bq=q; while(ISPATHSEP(file[q])) q++;
        continue;
        }
      if(base[p]==file[q]){
        p++;
        q++;
        continue;
        }
      break;
      }
#endif

    // Common prefix except for trailing path separator
    if((base[p]=='\0' || ISPATHSEP(base[p])) && (file[q]=='\0' || ISPATHSEP(file[q]))){
      bp=p;
      bq=q;
      }

    // Strip leading path character off, if any
    while(ISPATHSEP(file[bq])) bq++;

    // Non trivial
    if(file[bq]){
      FXString result;

      // Up to branch point
      while(base[bp]){
        while(ISPATHSEP(base[bp])) bp++;
        if(base[bp]){
          result.append(".." PATHSEPSTRING);
          while(base[bp] && !ISPATHSEP(base[bp])) bp++;
          }
        }

      // Append tail end
      result.append(&file[bq]);
      return result;
      }
    return ".";
    }
  return file;
  }


// Return relative path of file to the current directory
FXString FXPath::relative(const FXString& file){
  return FXPath::relative(FXSystem::getCurrentDirectory(),file);
  }


// Return true if file is inside base directory
//
// Examples:
//
//  Base       File         Result      Comment
//  /a/b/c     /a/b/c/d      yes        /a/b/c/d is under directory /a/b/c
//  /a/b/c     /a/b          no         /a/b is NOT under directory /a/b/c
//  a/b        a/b/c         yes        ./a/b/c is under directory ./a/b
//  a          b             no         ./b is NOT under ./a
//  a/b        a/c           no         ./a/c is NOT under ./a/b
//  /a/b/c     c             no         ./c is NOT (necessarily) under /a/b/c
//  a          /a/b          no         /a/b is NOT under ./a
//  .          b             yes        ./b is under .
//  ..         b             yes        ./b is under ./..
//  ../a       b             no         ./b is NOT under ../a
//  ./a/b      a/b           yes        ./a/b is under ./a/b
//  a/b        ./a/b/c       yes        ./a/b/c is under ./a/b
//  ./a/b      a/b           yes        ./a/b is under ./a/b
//  .          .             yes        . is under .
//  ..         .             yes        . is under ./..
//  ..         ..            yes        .. is under ..
//  .          ..            no         ./.. is NOT under .
//  ../a/b     ../a/b/c      yes        ../a/b/c is under ../a/b
//  ../a/b     ../d          no         ../d is NOT under ../a/b
//  (empty)    (something)   no         ./something is NOT under empty
FXbool FXPath::isInside(const FXString& base,const FXString& file){
  if(!base.empty() && !file.empty()){
    FXint p=0,q=0,v=0;
#if defined(WIN32)
    if(ISPATHSEP(base[p])){
      if(!ISPATHSEP(file[q])) return false;
      p++;
      q++;
      if(ISPATHSEP(base[p])){
        if(!ISPATHSEP(file[q])) return false;
        p++;
        q++;
        }
      }
    else if(Ascii::isLetter(base[p]) && base[p+1]==':'){
      if((Ascii::toLower(base[p])!=Ascii::toLower(file[q])) || (file[q+1]!=':')) return false;
      p+=2;
      q+=2;
      }
    while(base[p]){
      if(ISPATHSEP(base[p])){
        if(!ISPATHSEP(file[q])) return false;
        p++;
        q++;
        while(ISPATHSEP(base[p])) p++;
        while(ISPATHSEP(file[q])) q++;
        }
a:    if(base[p]=='.'){
        if(base[p+1]=='\0'){ p+=1; goto a; }
        if(ISPATHSEP(base[p+1])){ p+=2; goto a; }
        if(base[p+1]=='.'){
          if(base[p+2]=='\0'){ p+=2; v++; goto a; }
          if(ISPATHSEP(base[p+2])){ p+=3; v++; goto a; }
          }
        }
b:    if(file[q]=='.'){
        if(file[q+1]=='\0'){ q+=1; goto b; }
        if(ISPATHSEP(file[q+1])){ q+=2; goto b; }
        if(file[q+1]=='.'){
          if(file[q+2]=='\0'){ q+=2; v--; goto b; }
          if(ISPATHSEP(file[q+2])){ q+=3; v--; goto b; }
          }
        }
      if(v<0) return false;
      while(base[p] && !ISPATHSEP(base[p])){
        if(Ascii::toLower(base[p])!=Ascii::toLower(file[q])) return false;
        p++;
        q++;
        }
      }
    return true;
#else
    if(ISPATHSEP(base[p])){
      if(!ISPATHSEP(file[q])) return false;
      p++;
      q++;
      }
    while(base[p]){
      if(ISPATHSEP(base[p])){
        if(!ISPATHSEP(file[q])) return false;
        p++;
        q++;
        while(ISPATHSEP(base[p])) p++;
        while(ISPATHSEP(file[q])) q++;
        }
a:    if(base[p]=='.'){
        if(base[p+1]=='\0'){ p+=1; goto a; }
        if(ISPATHSEP(base[p+1])){ p+=2; goto a; }
        if(base[p+1]=='.'){
          if(base[p+2]=='\0'){ p+=2; v++; goto a; }
          if(ISPATHSEP(base[p+2])){ p+=3; v++; goto a; }
          }
        }
b:    if(file[q]=='.'){
        if(file[q+1]=='\0'){ q+=1; goto b; }
        if(ISPATHSEP(file[q+1])){ q+=2; goto b; }
        if(file[q+1]=='.'){
          if(file[q+2]=='\0'){ q+=2; v--; goto b; }
          if(ISPATHSEP(file[q+2])){ q+=3; v--; goto b; }
          }
        }
      if(v<0) return false;
      while(base[p] && !ISPATHSEP(base[p])){
        if(base[p]!=file[q]) return false;
        p++;
        q++;
        }
      }
    return true;
#endif
    }
  return false;
  }


// Convert path from using 'sepfm' to use 'septo' path-separators
FXString FXPath::convert(const FXString& file,FXchar septo,FXchar sepfm){
  if(!file.empty()){
    FXString result(file);
    FXint p=0,q=0;
#if defined(WIN32)
    if(result[q]==sepfm || result[q]==septo){                   // UNC
      result[p++]=septo; q++;
      if(result[q]==sepfm || result[q]==septo){
        result[p++]=septo; q++;
        while(result[q]==sepfm || result[q]==septo) q++;
        }
      }
    else if(Ascii::isLetter(result[q]) && result[q+1]==':'){    // C:
      result[p++]=result[q++];
      result[p++]=':'; q++;
      if(result[q]==sepfm || result[q]==septo){
        result[p++]=septo; q++;
        while(result[q]==sepfm || result[q]==septo) q++;
        }
      }
#else
    if(result[q]==sepfm || result[q]==septo){
      result[p++]=septo; q++;
      while(result[q]==sepfm || result[q]==septo) q++;
      }
#endif
    while(result[q]){
      if(result[q]==sepfm || result[q]==septo){
        result[p++]=septo; q++;
        while(result[q]==sepfm || result[q]==septo) q++;
        continue;
        }
      result[p++]=result[q++];
      }
    return result.trunc(p);
    }
  return FXString::null;
  }


// Up one level, given absolute path
FXString FXPath::upLevel(const FXString& file){
  if(!file.empty()){
    FXString result(file);
    FXint p=0,q=0,s;
#if defined(WIN32)
    if(ISPATHSEP(result[q])){                                   // UNC
      result[p++]=PATHSEP; q++;
      if(ISPATHSEP(result[q])){
        result[p++]=PATHSEP; q++;
        while(ISPATHSEP(result[q])) q++;
        }
      }
    else if(Ascii::isLetter(result[q]) && result[q+1]==':'){    // C:
      result[p++]=result[q++];
      result[p++]=':'; q++;
      if(ISPATHSEP(result[q])){
        result[p++]=PATHSEP; q++;
        while(ISPATHSEP(result[q])) q++;
        }
      }
#else
    if(ISPATHSEP(result[q])){
      result[p++]=PATHSEP; q++;
      while(ISPATHSEP(result[q])) q++;
      }
#endif
    s=p;
    while(result[q]){
      if(ISPATHSEP(result[q])){
        result[p++]=PATHSEP; q++;
        while(ISPATHSEP(result[q])) q++;
        if(result[q]) s=p-1;
        continue;
        }
      result[p++]=result[q++];
      }
    return result.trunc(s);
    }
  return PATHSEPSTRING;
  }


// Check if file represents absolute pathname
FXbool FXPath::isAbsolute(const FXString& file){
#if defined(WIN32)
  return ISPATHSEP(file[0]) || (Ascii::isLetter(file[0]) && file[1]==':' && ISPATHSEP(file[2]));
#else
  return ISPATHSEP(file[0]);
#endif
  }


// Does file represent topmost directory
FXbool FXPath::isTopDirectory(const FXString& file){
#if defined(WIN32)
  return (ISPATHSEP(file[0]) && (file[1]=='\0' || (ISPATHSEP(file[1]) && file[2]=='\0'))) || (Ascii::isLetter(file[0]) && file[1]==':' && (file[2]=='\0' || (ISPATHSEP(file[2]) && file[3]=='\0')));
#else
  return ISPATHSEP(file[0]) && file[1]=='\0';
#endif
  }


#if defined(WIN32)

// Check if file represents a file share
FXbool FXPath::isShare(const FXString& file){
  return ISPATHSEP(file[0]) && ISPATHSEP(file[1]) && file.find(PATHSEP,2)<0;
  }


// Return true if input path is a hidden file or directory
FXbool FXPath::isHidden(const FXString& file){
  if(!file.empty()){
    FXuint attrs;
#ifdef UNICODE
    FXnchar unifile[MAXPATHLEN];
    utf2ncs(unifile,file.text(),MAXPATHLEN);
    attrs=::GetFileAttributesW(unifile);
#else
    attrs=::GetFileAttributesA(file.text());
#endif
    if(attrs!=INVALID_FILE_ATTRIBUTES){
      return (attrs&FILE_ATTRIBUTE_HIDDEN)!=0;
      }
    }
  return false;
  }

#else

// Check if file represents a file share
FXbool FXPath::isShare(const FXString&){
  return false;
  }


// Return true if input path is a hidden file or directory
FXbool FXPath::isHidden(const FXString& file){
  if(!file.empty()){
    FXint i=file.length();
    while(0<i && !ISPATHSEP(file[i-1])){ --i; }
    return file[i]=='.';
    }
  return false;
  }

#endif


// Return valid part of absolute path
FXString FXPath::validPath(const FXString& file){
  if(FXPath::isAbsolute(file)){
    FXString result(file);
    while(!FXStat::exists(result) && !FXPath::isTopDirectory(result)){
      result=FXPath::upLevel(result);
      }
    return result;
    }
  return FXString::null;
  }


// Return true if path is valid
FXbool FXPath::isValidPath(const FXString& file){
  if(FXPath::isAbsolute(file)){
    return FXStat::exists(file);
    }
  return false;
  }

#if defined(WIN32)           // WINDOWS

// Enquote filename to make safe for shell
// Quoting with double quotes is needed:
//   - If force=true
//   - If white space before, in, or after letters
// Escaping is done when:
//   - Special characters (^ " < > | & * ?) are encountered
FXString FXPath::enquote(const FXString& file,FXbool force){
  FXString result(file);
  if(0<file.length()){
    FXint p,q,c,n;

    // Check if quotes needed, if not already forced
    if(!force && 0<=file.find_first_of(" \t\n\v\"")) force=true;

    // Measure new string size
    p=q=n=0;
    while(p<=file.length()){
      switch(file[p++]){
        case '\0':              // End of string
          if(force){
            q+=n;               // Extra n backslashes makes for 2n backslashes
            }
          continue;
        case '\\':              // Backslashes
          q++;
          n++;
          continue;
        case '"':               // Quotes
          if(force){
            q+=n+2;             // Extra n+1 backslashes makes for 2n+1 backslashes
            }
          else{
            q+=2;               // Escaped normally
            }
          n=0;
          continue;
        case '^':             // Escape character
        case '<':             // Redirection
        case '>':
        case '(':
        case ')':
        case '|':             // Pipe
        case '%':             // Environment variables
        case '!':             // Wildcard
        case '&':             // Command separators
        case '*':             // Wildcard
        case '?':
          if(!force) q++;
        default:                // Normal characters
          q++;
          n=0;
          continue;
        }
      }

    // Surround by quotes as well
    if(force) q+=2;

    // Size changed, so transoformation needed
    if(result.length()<q){
      result.length(q);         // Make longer if quoted
      p=q=0;
      if(force) result[q++]='"';
      while(p<=file.length()){
        switch(c=file[p++]){
          case '\0':            // End of string
            if(force){
              while(--n>=0) result[q++]='\\';
              }
            continue;
          case '\\':            // Backslashes
            result[q++]='\\';
            n++;
            continue;
          case '"':             // Quotes not preceeded by backslashes
            if(force){
              while(--n>=0) result[q++]='\\';
              result[q++]='\\';
              }
            else{
              result[q++]='^';
              }
            result[q++]='"';
            n=0;
            continue;
          case '^':             // Escape character
          case '<':             // Redirection
          case '>':
          case '(':
          case ')':
          case '|':             // Pipe
          case '%':             // Environment variables
          case '!':             // Wildcard
          case '&':             // Command separators
          case '*':             // Wildcard
          case '?':
            if(!force) result[q++]='^';
          default:              // Normal characters
            result[q++]=c;
            n=0;
            continue;
          }
        }
      if(force) result[q++]='"';
      }
    FXASSERT(result.length()==q);
    }
  return result;
  }


// Decode quoted or escaped filename.
// Examples:
//
//  Input       Result          Comment
//  "a b"       a b             Quotes serve as optional argument delimiters.
//
//  \"          "               Escaped quotes are converted back to '"'.
//
//  \\\"        \"              Odd number of \ followed by " correspond to half that
//  \\\\\"      \\"             number of \ followed by a ".
//
//  a\\"b c"    a\b c           An even number of \ followed by a " correspond to half that
//  a\\\\"b c"  a\\b c          number of \, with quotes serving as an argument delimiters.
//
//  a\b         a\b             When not followed by a ", a \ is copied literally.
//  a\\b        a\\b
//
//  ^<file      <file           Caret ^ serves as escape in non quoted string.
//  a^^b        a^b
//
//  "^>file"    ^>file          Caret passed unchanged when inside quoted string.
//  "ab^\c"     ab^\c
FXString FXPath::dequote(const FXString& file){
  FXString result(file);
  if(0<result.length()){
    FXint e=result.length(),b=0,r=0,q=0,n=0;

    // Trim tail
    while(0<e && Ascii::isSpace(file[e-1])) --e;

    // Trim head
    while(b<e && Ascii::isSpace(file[b])) ++b;

    // Dequote the rest
    while(b<e){
      while(file[b]=='\\'){     // Track runs of backslashes
        result[r++]=file[b++];
        n++;
        continue;
        }
      if(file[b]=='"'){         // Start or end of quoted part
        if(n&1){                // Quotes were escaped by odd number of backslashes
          r=r-n/2-1;
          result[r++]='"';      // So insert the quote
          b++;
          }
        else{                   // Quotes not escaped
          r=r-n/2;
          q=!q;                 // So toggle the quotes flag
          b++;
          }
        n=0;
        continue;
        }
      if(file[b]=='^'){         // Escape character if not not in quoted part
        if(!q && b+1<e) b++;
        }
      result[r++]=file[b++];    // Normal characters are copied
      n=0;
      }
    result.trunc(r);
    }
  return result;
  }

#else                         // UNIX


// Enquote filename to make safe for shell
// Quoting with single quote is needed:
//   - If force=true
//   - If white space before, in, or after letters
//   - If any special character (\ ! " $ & ( ) ; < > | ` ^ * + ? [ ]) is found
// Escaping is done when:
//   - Quote character (') are encountered
FXString FXPath::enquote(const FXString& file,FXbool force){
  FXString result(file);
  if(0<file.length()){
    FXint p=0,q=0,e=0,c;
    while(p<file.length()){
      switch(file[p++]){
        case '\'':              // Quote needs to be escaped to ...'\''....
          q+=2;                 // Two if quote is not inside quotation
          e+=2;                 // Two more if it is
          continue;
        case '\\':              // Back slash
        case '!':               // Special in csh
        case '"':
        case '$':               // Variable substitution
        case '&':
        case '(':
        case ')':
        case ';':
        case '<':               // Redirections, pipe
        case '>':
        case '|':
        case '`':               // Command substitution
        case '^':               // Special in sh
        case '*':               // Wildcard characters
        case '+':
        case '?':
        case '[':
        case ']':
        case '\t':              // White space
        case '\n':
        case '\v':
        case ' ':
          force=true;           // Force quotes
          q++;
          continue;
        case '#':               // Comments
        case '~':               // Username substitution
          if(p==1) force=true;  // Force quotes if at beginning
        default:                // Normal character
          q++;
          continue;
        }
      }
    if(force) q+=e+2;           // Each escape adds two, quoting adds two more
    if(result.length()<q){
      result.length(q);         // Make longer if quoted
      p=q=0;
      if(force) result[q++]='\'';
      while(p<file.length()){
        if((c=file[p++])=='\''){        // Quote needs to be escaped
          if(force) result[q++]='\'';   // End quotation run first
          result[q++]='\\';
          result[q++]=c;
          if(force) result[q++]='\'';   // Start next quotation run
          continue;
          }
        result[q++]=c;
        }
      if(force) result[q++]='\'';
      }
    FXASSERT(result.length()==q);
    }
  return result;
  }


// Decode filename to get original again
FXString FXPath::dequote(const FXString& file){
  FXString result(file);
  if(0<result.length()){
    FXint e=result.length(),b=0,r=0,q=0;

    // Trim tail
    while(0<e && Ascii::isSpace(file[e-1])) --e;

    // Trim head
    while(b<e && Ascii::isSpace(file[b])) ++b;

    // Dequote the rest
    while(b<e){
      if(file[b]=='\''){ q=!q; b++; continue; }
      if(file[b]=='\\' && file[b+1]=='\'' && !q){ b++; }
      result[r++]=file[b++];
      }

    // Trunc to size
    result.trunc(r);
    }
  return result;
  }


#endif


// Skip over part of pattern
//
// This is a bit complex: we need to count matching parentheses, while
// also keeping track of whether we're inside a charset, as parentheses
// in a charset are not grouping parentheses.
// Charsets are delimited by brackets, but a closing bracket appearing
// as the first character in the set does not close the charset, but is
// taken as just a character.  Note, the first actual character in a
// charset may actually follow a set-negation character, '!' or '^'.
// If alt=true, we don't scan all the way to the end of the group, but
// just skip to the start of the next alternative, which immediately
// follows a '|' or ',' character.
// A last and final concern is the escape sequence (if enabled), which
// prevents interpretation of the escaped character as a special directive.
static const FXchar* skip(const FXchar* p,FXuint flags,FXbool alt){
  FXint set=0;          // Characters in set [ ]
  FXint brk=0;          // Bracket set
  FXint par=0;          // Group level
  FXint neg=0;          // Negated
n:switch(*p){
    case '\0':
      goto x;
    case '[':           // Enter character set [ ]
      p++;
      if(!brk){ brk=1; set=0; neg=0; goto n; }
      set++;
      goto n;
    case ']':           // Leave character set [ ]
      p++;
      if(brk && set){ brk=0; goto n; }
      set++;
      goto n;
    case '!':
    case '^':
      p++;
      if(!neg && !set){ neg=1; goto n; }
      set++;
      goto n;
    case '(':           // Enter sub group ( )
      p++;
      if(!brk){ ++par; }
      set++;
      goto n;
    case ')':           // Leave sub group ( )
      if(!brk){ if(--par<0) goto x; }
      p++;
      set++;
      goto n;
    case ',':           // Separation of alternatives
    case '|':
      if(!brk && !par && alt){ goto x; }
      p++;
      set++;
      goto n;
    case '\\':          // Escape code
      if(!(flags&FXPath::NoEscape)){ if(*++p=='\0') goto x; }
      // FALL //
    default:            // Regular character
      p=wcinc(p);       // Next unicode character
      set++;            // One more in set
      goto n;
    }
x:return p;
  }


// Perform match
//
// Special pattern characters are interpreted as follows:
//
//   ?   Normally matches a single unicode character. However, when the DotFile flag is passed,
//       the ? does NOT match a '.' if it appears at the start of the string, or if it follows a
//       '/' and the PathName flag is also passed.
//
//   *   Normally matches zero or more unicode characters. However, when the DotFile flag is passed,
//       the * does NOT match a '.' if the '.' appears at the start of the string, or if it follows a
//       '/' and the PathName flag is also passed.
//
//  [ ]  Character set matches a single unicode character in the set.  However, then the DotFile flag
//       is passed, the [] does NOT match a '.' if it appears at the start of the string, or if it follows
//       a '/' and the PathName flag is also passed.
//       A set is negated (matches when the corresponding character is NOT in the set), by following the
//       opening '[' with '^' or '!'.
//
//   \   Escaped characters match the unicode character.  If \ is NOT followed by a character, the match
//       will fail.
//
// ( | ) Will start, separate, and end a group of alternatives, each of which may contain pattern
//       characters as well as sub-groups thereof.
//
static FXbool domatch(const FXchar* string,const FXchar* s,const FXchar* p,FXuint flags){
  const FXchar* q;
  FXwchar pp,qq,ss;
  FXbool neg,ok;
  //FXTRACE((1,"domatch(string: \"%s\", pattern: \"%s\", flags: %x)\n",s,p,flags));
  while(*p!='\0'){
    switch(*p){
      case '(':         // Start subpattern
        p++;
        q=skip(p,flags,false);                                  // End of sub group
        if(*q!=')') return false;                               // Missing ')'
        while(p<q){
          if(domatch(string,s,p,flags)) return true;
          p=skip(p,flags,true);                                 // End of alternative
          if(*p!=',' && *p!='|') continue;
          p++;
          }
        return false;
      case ')':         // End subpattern
        p++;
        break;
      case '|':         // Alternatives
      case ',':
        p=skip(p+1,flags,false);                                // Continue to match the rest
        break;
      case '?':         // Single character wildcard
        p++;                                                    // Eat '?'
        if(*s=='\0') return false;
        if(ISPATHSEP(*s) && (flags&FXPath::PathName)) return false;
        if((*s=='.') && (flags&FXPath::DotFile) && ((s==string) || (ISPATHSEP(*(s-1)) && (flags&FXPath::PathName)))) return false;
        s=wcinc(s);
        break;
      case '*':         // Multiple character wildcard
        while(*p=='*') p++;                                     // Eat '*'
        while(*s!='\0'){
          if(domatch(string,s,p,flags)) return true;
          if((*s=='.') && (flags&FXPath::DotFile) && ((s==string) || (ISPATHSEP(*(s-1)) && (flags&FXPath::PathName)))) return false;
          if(ISPATHSEP(*s) && (flags&FXPath::PathName)) return false;
          s=wcinc(s);
          }
        break;
      case '[':         // Single character against character-set
        p++;                                                    // Eat '['
        if(*s=='\0') return false;
        if(ISPATHSEP(*s) && (flags&FXPath::PathName)) return false;
        if((*s=='.') && ((s==string) || ISPATHSEP(*(s-1))) && (flags&FXPath::DotFile)) return false;
        neg=(*p=='!' || *p=='^');
        if(neg) p++;
        ss=wc(s);
        if(flags&FXPath::CaseFold){ ss=Unicode::toLower(ss); }
        s=wcinc(s);
        ok=false;
        do{
          if(*p=='\\' && !(flags&FXPath::NoEscape)) p++;
          if(*p=='\0') return false;
          pp=wc(p);
          if(flags&FXPath::CaseFold){ pp=Unicode::toLower(pp); }
          p=wcinc(p);
          if(*p=='-' && *(p+1)!=']'){                           // Range match
            p++;
            if(*p=='\\' && !(flags&FXPath::NoEscape)) p++;
            if(*p=='\0') return false;
            qq=wc(p);
            if(flags&FXPath::CaseFold){ qq=Unicode::toLower(qq); }
            p=wcinc(p);
            if(pp<=ss && ss<=qq) ok=true;
            }
          else{                                                 // Single match
            if(pp==ss) ok=true;
            }
          }
        while(*p!=']');
        p++;
        if(ok==neg) return false;
        break;
      case '\\':        // Escaped character follows
        if(!(flags&FXPath::NoEscape)){ if(*++p=='\0') return false; }
        // FALL //
      default:          // Match characters against pattern
        pp=wc(p);
        ss=wc(s);
        if(flags&FXPath::CaseFold){
          pp=Unicode::toLower(pp);
          ss=Unicode::toLower(ss);
          }
        if(pp!=ss) return false;
        s=wcinc(s);
        p=wcinc(p);
        break;
      }
    }
  return (*s=='\0') || (ISPATHSEP(*s) && (flags&FXPath::LeadDir));
  }


// Match filename against a pattern, subject to flags
FXbool FXPath::match(const FXchar* string,const FXchar* pattern,FXuint flags){
  const FXchar* end=skip(pattern,flags,false);  // Check pattern syntax
  if(*end=='\0'){
    while(*pattern){
      if(domatch(string,string,pattern,flags)) return true;
      pattern=skip(pattern,flags,true);
      if(*pattern!=',' && *pattern!='|') break;
      pattern++;
      }
    }
  return false;
  }


// Match filename against pattern (like *, ?, [^a-z], and so on)
FXbool FXPath::match(const FXString& file,const FXchar* pattern,FXuint flags){
  return FXPath::match(file.text(),pattern,flags);
  }


// Match filename against pattern (like *, ?, [^a-z], and so on)
FXbool FXPath::match(const FXString& file,const FXString& pattern,FXuint flags){
  return FXPath::match(file.text(),pattern.text(),flags);
  }


// Generate unique filename of the form pathnameXXX.ext, where pathname.ext is the
// original input file, and XXX is a number, possibly empty, that makes the file unique.
FXString FXPath::unique(const FXString& file){
  if(!FXStat::exists(file)) return file;
  FXString ext=FXPath::extension(file);
  FXString path=FXPath::stripExtension(file);           // Use the new API (Jeroen)
  FXString filename;
  FXint count=0;
  if(!ext.empty()) ext.prepend('.');            // Only add period when non-empty extension
  while(count<1000){
    filename.format("%s%i%s",path.text(),count,ext.text());
    if(!FXStat::exists(filename)) return filename;      // Return result here (Jeroen)
    count++;
    }
  return FXString::null;
  }


// Search pathlist for file
FXString FXPath::search(const FXString& pathlist,const FXString& file){
  FXTRACE((100,"FXPath::search(\"%s\",\"%s\")\n",pathlist.text(),file.text()));
  if(!file.empty()){
    FXString path;
    FXint beg,end;
    if(FXPath::isAbsolute(file)){
      if(FXStat::exists(file)) return file;
      return FXString::null;
      }
    for(beg=0; pathlist[beg]; beg=end){
      while(pathlist[beg]==PATHLISTSEP) beg++;
      end=beg;
      while(pathlist[end] && pathlist[end]!=PATHLISTSEP) end++;
      if(beg==end) break;
      path=FXPath::absolute(FXPath::expand(pathlist.mid(beg,end-beg)),file);
      if(FXStat::exists(path)) return path;
      }
    }
  return FXString::null;
  }


// Relativize to path list
FXString FXPath::relativize(const FXString& pathlist,const FXString& file){
  FXString result(file);
  if(!file.empty()){
    FXint beg,end;
    FXString base,rr,r;
    for(beg=0; pathlist[beg]; beg=end){
      while(pathlist[beg]==PATHLISTSEP) beg++;
      for(end=beg; pathlist[end] && pathlist[end]!=PATHLISTSEP; end++){}
      if(beg==end) break;
      base=FXPath::absolute(FXPath::expand(pathlist.mid(beg,end-beg)));
      if(isInside(base,file)){
        r=FXPath::relative(base,file);
        if(r.length()<result.length()){         // ??
          if(FXPath::search(pathlist,r)==file){
            result=r;
            }
          }
        }
      }
    }
  return result;
  }


// Check if file has executable extension
FXbool FXPath::hasExecExtension(const FXString& file){
#if defined(WIN32)
  if(!file.empty()){
    FXString pathext(FXSystem::getExecExtensions());
    FXint beg=0,end;
    do{
      end=beg;
      while(end<pathext.length() && pathext[end]!=PATHLISTSEP) end++;
      if(0<=(file.length()-end+beg) && comparecase(&file[file.length()-end+beg],&pathext[beg],end-beg)==0) return true;
      beg=end+1;
      }
    while(end<pathext.length());
    }
#endif
  return false;
  }


}
