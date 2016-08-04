/********************************************************************************
*                                                                               *
*                       H a s h   T a b l e   C l a s s                         *
*                                                                               *
*********************************************************************************
* Copyright (C) 2003,2016 by Jeroen van der Zijp.   All Rights Reserved.        *
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
#ifndef FXHASH_H
#define FXHASH_H

namespace FX {


/**
* A hash table for mapping pointers to pointers.
* Any value may be used as a key, except 0 and -1.
*/
class FXAPI FXHash {
protected:
  struct Entry {
    FXptr name;
    FXptr data;
    };
protected:
  Entry  *table;
protected:

  // Change size of the table & hash existing contents
  FXbool no(FXival n);

  // Change number of used entries
  void used(FXival u){ ((FXival*)table)[-2]=u; }

  // Change number of free entries
  void free(FXival f){ ((FXival*)table)[-3]=f; }

  // Resize the table to the given size, keeping contents
  FXbool resize(FXival n);
public:

  /**
  * Construct empty hash table.
  */
  FXHash();

  /**
  * Construct from another table.
  */
  FXHash(const FXHash& other);

  /**
  * Return the total number of slots in the table.
  */
  FXival no() const { return ((FXival*)table)[-1]; }

  /**
  * Return number of used slots in the table.
  */
  FXival used() const { return ((FXival*)table)[-2]; }

  /**
  * Return number of free slots in the table.
  */
  FXival free() const { return ((FXival*)table)[-3]; }

  /**
  * See if hash table is empty
  */
  FXbool empty() const { return ((FXival*)table)[-1]<=1; }

  /**
  * Assign from another table.
  */
  FXHash &operator=(const FXHash& other);

  /**
  * Adopt table from another; the other table becomes empty.
  */
  FXHash& adopt(FXHash& other);

  /**
  * Find position of given key, returning -1 if not found.
  */
  FXival find(FXptr name) const;

  /**
  * Return reference to slot assocated with given key.
  */
  FXptr& at(FXptr name);

  /**
  * Return constant reference to slot assocated with given key.
  */
  const FXptr& at(FXptr name) const;

  /**
  * Return reference to slot assocated with given key.
  */
  FXptr& operator[](FXptr name){ return at(name); }

  /**
  * Return constant reference to slot assocated with given key.
  */
  const FXptr& operator[](FXptr name) const { return at(name); }

  /**
  * Replace key in table, overwriting the old value if the
  * given key already exists.  Returns the old value of the key.
  */
  FXptr insert(FXptr name,FXptr data=NULL){ return swap(data,at(name)); }

  /**
  * Remove key from the table. Returns the old value of the key.
  */
  FXptr remove(FXptr name);

  /**
  * Erase entry from table at pos, returning old value.
  */
  FXptr erase(FXival pos);

  /**
  * Return true if slot is not occupied by a key.
  */
  FXbool empty(FXival pos) const { return (table[pos].name==(FXptr)0L)||(table[pos].name==(FXptr)-1L); }

  /**
  * Return key at position pos.
  */
  FXptr key(FXival pos) const { return table[pos].name; }

  /**
  * Return reference to data pointer at position pos.
  */
  FXptr& value(FXival pos){ return table[pos].data; }

  /**
  * Return constant reference data pointer at position pos.
  */
  const FXptr& value(FXival pos) const { return table[pos].data; }

  /**
  * Clear hash table.
  */
  void clear();

  /// Destructor
 ~FXHash();
  };


/// Hash table of pointers to KEYTYPE to pointers of VALUETYPE
template<typename KEYTYPE,typename VALUETYPE>
class FXHashOf : public FXHash {
public:

  /// Default constructor
  FXHashOf(){}

  /// Copy constructor
  FXHashOf(const FXHashOf<KEYTYPE,VALUETYPE>& src):FXHash(src){}

  /// Return reference to slot assocated with given key
  VALUETYPE*& at(KEYTYPE* name){ return (VALUETYPE*&)FXHash::at((FXptr)name); }

  /// Return constant reference to slot assocated with given key
  VALUETYPE *const& at(KEYTYPE* name) const { return (VALUETYPE *const&)FXHash::at((FXptr)name); }

  /// Return reference to slot assocated with given key
  VALUETYPE*& operator[](KEYTYPE* name){ return (VALUETYPE*&)FXHash::at((FXptr)name); }

  /// Return constant reference to slot assocated with given key
  VALUETYPE *const& operator[](KEYTYPE* name) const { return (VALUETYPE *const&)FXHash::at((FXptr)name); }

  /// Insert association with given key; return old value, if any
  VALUETYPE* insert(KEYTYPE* name,VALUETYPE* data=NULL){ return (VALUETYPE*)FXHash::insert((FXptr)name,(FXptr)data); }

  /// Remove association with given key; return old value, if any
  VALUETYPE* remove(KEYTYPE* name){ return (VALUETYPE*)FXHash::remove((FXptr)name); }

  /// Erase data at pos in the table; return old value, if any
  VALUETYPE* erase(FXival pos){ return (VALUETYPE*)FXHash::erase(pos); }

  /// Return key at position pos
  KEYTYPE* key(FXival pos) const { return (KEYTYPE*)FXHash::key(pos); }

  /// Return reference to slot at position pos
  VALUETYPE*& value(FXival pos){ return (VALUETYPE*&)FXHash::value(pos); }

  /// Return constant reference to slot at position pos
  VALUETYPE *const& value(FXival pos) const { return (VALUETYPE *const&)FXHash::value(pos); }
  };

}

#endif
