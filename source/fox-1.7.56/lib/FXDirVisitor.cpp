/********************************************************************************
*                                                                               *
*                     D i r e c t o r y   V i s i t o r                         *
*                                                                               *
*********************************************************************************
* Copyright (C) 2008,2016 by Jeroen van der Zijp.   All Rights Reserved.        *
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
#include "FXArray.h"
#include "FXHash.h"
#include "FXStream.h"
#include "FXString.h"
#include "FXStat.h"
#include "FXFile.h"
#include "FXPath.h"
#include "FXDir.h"
#include "FXDirVisitor.h"

/*
  Notes:

  - There are three return codes to influence processing:

      0 : Skip item, move to next
      1 : Continue with processing.
      2 : Bail on the whole thing.

  - Automatically skip directories already being visited to avoid circular symlinks
    from causing infinite recursion.
  - Also skip directories with insufficient permissions.
  - Recursion limiter feature added; allows one to stop below a certain level.
*/


using namespace FX;

/*******************************************************************************/

namespace FX {


// Keep track of visited directories
struct FXDirVisitor::Seen {
  Seen   *next;
  FXlong  node;
  };


// Recurse, keeping track of where we've been already
FXuint FXDirVisitor::recurse(const FXString& path,Seen *seen,FXint depth){
  if(0<depth){
    FXStat data;
    if(FXStat::statLink(path,data)){
      if(data.isDirectory()){                     // Directory
        FXuint code;
        for(Seen *s=seen; s; s=s->next){
          if(data.index()==s->node) return 0;     // Skip if we've been here already
          }
        if((code=enter(path))==1){                // Conditionally enter subdirectories
          Seen here={seen,data.index()};
          FXDir directory(path);
          FXString name;
          while(directory.next(name)){
            if(!(name[0]=='.' && (name[1]==0 || (name[1]=='.' && name[2]==0)))){
              if(recurse(path+(ISPATHSEP(path.tail())?"":PATHSEPSTRING)+name,&here,depth-1)==2){
                leave(path);
                return 2;                         // Bail
                }
              }
            }
          return leave(path);
          }
        return code;
        }
      return visit(path);                         // Regular file
      }
    }
  return 0;
  }


// Recursively traverse starting from path
FXuint FXDirVisitor::traverse(const FXString& path,FXint depth){
  return recurse(path,NULL,depth);
  }


// Enter directory
FXuint FXDirVisitor::enter(const FXString&){
  return 1;
  }


// Handle file
FXuint FXDirVisitor::visit(const FXString&){
  return 1;
  }


// Leave directory
FXuint FXDirVisitor::leave(const FXString&){
  return 1;
  }


// Destructor
FXDirVisitor::~FXDirVisitor(){
  }

/*******************************************************************************/

// Recursively traverse starting from path
FXuint FXGlobVisitor::traverse(const FXString& path,const FXString& wild,FXuint opts,FXint depth){
  wildcard=wild;
  options=opts;
  return recurse(path,NULL,depth);
  }


// Enter directory
FXuint FXGlobVisitor::enter(const FXString& path){
  FXuint mode=(options&FXDir::CaseFold)?(FXPath::NoEscape|FXPath::CaseFold):(FXPath::NoEscape);
#ifdef WIN32
  return !(options&FXDir::NoDirs) && ((options&FXDir::HiddenDirs) || !FXStat::isHidden(path)) && ((options&FXDir::AllDirs) || FXPath::match(path,wildcard,mode));
#else
  return !(options&FXDir::NoDirs) && ((options&FXDir::HiddenDirs) || !FXPath::isHidden(path)) && ((options&FXDir::AllDirs) || FXPath::match(path,wildcard,mode));
#endif
  }


// Handle file
FXuint FXGlobVisitor::visit(const FXString& path){
  FXuint mode=(options&FXDir::CaseFold)?(FXPath::NoEscape|FXPath::CaseFold):(FXPath::NoEscape);
#ifdef WIN32
  return !(options&FXDir::NoFiles) && ((options&FXDir::HiddenFiles) || !FXStat::isHidden(path)) && ((options&FXDir::AllFiles) || FXPath::match(path,wildcard,mode));
#else
  return !(options&FXDir::NoFiles) && ((options&FXDir::HiddenFiles) || !FXPath::isHidden(path)) && ((options&FXDir::AllFiles) || FXPath::match(path,wildcard,mode));
#endif
  }


// Leave directory
FXuint FXGlobVisitor::leave(const FXString&){
  return 1;
  }


// Destructor
FXGlobVisitor::~FXGlobVisitor(){
  }

/*******************************************************************************/



// Create new glob counting visitor
FXGlobCountVisitor::FXGlobCountVisitor():countFolders(0),countFiles(0),countBytes(0),maxDepth(0),depth(0){
  }

// Copy glob counting visitor
FXGlobCountVisitor::FXGlobCountVisitor(const FXGlobCountVisitor& org):countFolders(org.countFolders),countFiles(org.countFiles),countBytes(org.countBytes),maxDepth(org.maxDepth),depth(0){
  }


// Start traversal of path
FXuint FXGlobCountVisitor::traverse(const FXString& path,const FXString& wild,FXuint opts,FXint limit){
  countFolders=countFiles=countBytes=maxDepth=depth=0;
  return FXGlobVisitor::traverse(path,wild,opts,limit);
  }


// Enter directory
FXuint FXGlobCountVisitor::enter(const FXString& path){
  if(FXGlobVisitor::enter(path)){
    countFolders++;
    depth++;
    return 1;
    }
  return 0;
  }


// He mister tally man, tally me banana...
FXuint FXGlobCountVisitor::visit(const FXString& path){
  if(FXGlobVisitor::visit(path)){
    countBytes+=FXStat::size(path);
    countFiles++;
    return 1;
    }
  return 0;
  }


// Leave directory
FXuint FXGlobCountVisitor::leave(const FXString& path){
  if(FXGlobVisitor::leave(path)){
    maxDepth=FXMAX(maxDepth,depth);
    depth--;
    return 1;
    }
  return 0;
  }


// Destructor
FXGlobCountVisitor::~FXGlobCountVisitor(){
  }


}
