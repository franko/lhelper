/********************************************************************************
*                                                                               *
*                            O b j e c t   L i s t                              *
*                                                                               *
*********************************************************************************
* Copyright (C) 1997,2016 by Jeroen van der Zijp.   All Rights Reserved.        *
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
#ifndef FXOBJECTLIST_H
#define FXOBJECTLIST_H

#ifndef FXOBJECT_H
#include "FXObject.h"
#endif

namespace FX {


/// List of pointers to objects
class FXAPI FXObjectList {
protected:
  FXObject **ptr;
public:

  /// Default constructor
  FXObjectList();

  /// Copy constructor
  FXObjectList(const FXObjectList& src);

  /// Construct and init with single object
  FXObjectList(FXObject* object);

  /// Construct and init with n copies of object
  FXObjectList(FXObject* object,FXival n);

  /// Construct and init with list of objects
  FXObjectList(FXObject** objects,FXival n);

  /// Assignment operator
  FXObjectList& operator=(const FXObjectList& orig);

  /// Return number of objects
  FXival no() const { return *((FXival*)(ptr-1)); }

  /// Set number of objects
  FXbool no(FXival num);

  /// Indexing operator
  FXObject*& operator[](FXival i){ return ptr[i]; }
  FXObject* const& operator[](FXival i) const { return ptr[i]; }

  /// Indexing operator
  FXObject*& at(FXival i){ return ptr[i]; }
  FXObject* const& at(FXival i) const { return ptr[i]; }

  /// First element in list
  FXObject*& head(){ return ptr[0]; }
  FXObject* const& head() const { return ptr[0]; }

  /// Last element in list
  FXObject*& tail(){ return ptr[no()-1]; }
  FXObject* const& tail() const { return ptr[no()-1]; }

  /// Access to content array
  FXObject** data(){ return ptr; }
  FXObject *const * data() const { return ptr; }

  /// Adopt objects from orig, leaving orig empty
  FXObjectList& adopt(FXObjectList& orig);

  /// Find object in list, searching forward; return position or -1
  FXival find(const FXObject *object,FXival pos=0) const;

  /// Find object in list, searching backward; return position or -1
  FXival rfind(const FXObject *object,FXival pos=2147483647) const;

  /// Assign object to list
  FXbool assign(FXObject* object);

  /// Assign n copies of object to list
  FXbool assign(FXObject* object,FXival n);

  /// Assign n objects to list
  FXbool assign(FXObject** objects,FXival n);

  /// Assign objects to list
  FXbool assign(const FXObjectList& objects);

  /// Insert object at certain position
  FXbool insert(FXival pos,FXObject* object);

  /// Insert n copies of object at specified position
  FXbool insert(FXival pos,FXObject* object,FXival n);

  /// Insert n objects at specified position
  FXbool insert(FXival pos,FXObject** objects,FXival n);

  /// Insert objects at specified position
  FXbool insert(FXival pos,const FXObjectList& objects);

  /// Prepend object
  FXbool prepend(FXObject* object);

  /// Prepend n copies of object
  FXbool prepend(FXObject* object,FXival n);

  /// Prepend n objects
  FXbool prepend(FXObject** objects,FXival n);

  /// Prepend objects
  FXbool prepend(const FXObjectList& objects);

  /// Append object
  FXbool append(FXObject* object);

  /// Append n copies of object
  FXbool append(FXObject* object,FXival n);

  /// Append n objects
  FXbool append(FXObject** objects,FXival n);

  /// Append objects
  FXbool append(const FXObjectList& objects);

  /// Replace object at position by given object
  FXbool replace(FXival pos,FXObject* object);

  /// Replaces the m objects at pos with n copies of object
  FXbool replace(FXival pos,FXival m,FXObject* object,FXival n);

  /// Replaces the m objects at pos with n objects
  FXbool replace(FXival pos,FXival m,FXObject** objects,FXival n);

  /// Replace the m objects at pos with objects
  FXbool replace(FXival pos,FXival m,const FXObjectList& objects);

  /// Remove object at pos
  FXbool erase(FXival pos);

  /// Remove n objects at pos
  FXbool erase(FXival pos,FXival n);

  /// Remove object
  FXbool remove(const FXObject* object);

  /// Push object to end
  FXbool push(FXObject* object);

  /// Pop object from end
  FXbool pop();

  /// Remove all objects
  void clear();

  /// Save to a stream
  void save(FXStream& store) const;

  /// Load from a stream
  void load(FXStream& store);

  /// Destructor
 ~FXObjectList();
  };


/// List to pointers to objects of TYPE
template<typename TYPE>
class FXObjectListOf : public FXObjectList {
public:

  /// Default constructor
  FXObjectListOf(){}

  /// Copy constructor
  FXObjectListOf(const FXObjectListOf<TYPE>& src):FXObjectList(src){ }

  /// Construct and init with single object
  FXObjectListOf(TYPE* object):FXObjectList(reinterpret_cast<FXObject*>(object)){ }

  /// Construct and init with n copies of object
  FXObjectListOf(TYPE* object,FXival n):FXObjectList(reinterpret_cast<FXObject*>(object),n){ }

  /// Construct and init with list of objects
  FXObjectListOf(TYPE** objects,FXival n):FXObjectList(reinterpret_cast<FXObject**>(objects),n){ }

  /// Indexing operator
  TYPE*& operator[](FXival i){ return reinterpret_cast<TYPE*&>(ptr[i]); }
  TYPE *const& operator[](FXival i) const { return reinterpret_cast<TYPE*const&>(ptr[i]); }

  /// Indexing operator
  TYPE*& at(FXival i){ return reinterpret_cast<TYPE*&>(ptr[i]); }
  TYPE *const& at(FXival i) const { return reinterpret_cast<TYPE*const&>(ptr[i]); }

  /// First element in list
  TYPE*& head(){ return reinterpret_cast<TYPE*&>(ptr[0]); }
  TYPE* const& head() const { return reinterpret_cast<TYPE*const&>(ptr[0]); }

  /// Last element in list
  TYPE*& tail(){ return reinterpret_cast<TYPE*&>(ptr[no()-1]); }
  TYPE* const& tail() const { return reinterpret_cast<TYPE* const&>(ptr[no()-1]); }

  /// Access to content array
  TYPE** data(){ return reinterpret_cast<TYPE**>(ptr); }
  TYPE *const * data() const { return reinterpret_cast<TYPE*const*>(ptr); }

  /// Adopt objects from src, leaving src empty
  FXObjectListOf<TYPE>& adopt(FXObjectListOf<TYPE>& src){ return reinterpret_cast<FXObjectListOf<TYPE>&>(FXObjectList::adopt(src)); }
  };

}

#endif
