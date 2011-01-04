-----------------------------------------------------------------------
--                          G N A T C O L L                          --
--                                                                   --
--                    Copyright (C) 2011, AdaCore                    --
--                                                                   --
-- This is free software;  you can redistribute it and/or modify  it --
-- under the terms of the GNU General Public License as published by --
-- the Free Software Foundation; either version 2 of the License, or --
-- (at your option) any later version.                               --
--                                                                   --
-- As a special exception, if other files instantiate generics  from --
-- this unit, or you link this  unit with other files to produce  an --
-- executable, this unit does not by itself cause the resulting exe- --
-- cutable  to be covered by  the  GNU General  Public License. This --
-- exception does not however  invalidate any other reasons why  the --
-- executable  file  might  be  covered  by  the  GNU General Public --
-- License.                                                          --
--                                                                   --
-- This program is  distributed in the hope that it will be  useful, --
-- but  WITHOUT ANY WARRANTY;  without even the  implied warranty of --
-- MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU --
-- General Public License for more details. You should have received --
-- a copy of the GNU General Public License along with this program; --
-- if not,  write to the  Free Software Foundation, Inc.,  59 Temple --
-- Place - Suite 330, Boston, MA 02111-1307, USA.                    --
-----------------------------------------------------------------------

with Ada.Characters.Handling;     use Ada.Characters.Handling;
with Ada.Containers;              use Ada.Containers;
with Ada.Exceptions;              use Ada.Exceptions;
with Ada.Strings.Fixed;           use Ada.Strings, Ada.Strings.Fixed;
with Ada.Strings.Maps;            use Ada.Strings.Maps;
with Ada.Text_IO;                 use Ada.Text_IO;
with GNAT.Strings;                use GNAT.Strings;
with GNATCOLL.Mmap;               use GNATCOLL.Mmap;
with GNATCOLL.Utils;              use GNATCOLL.Utils;

package body GNATCOLL.SQL.Inspect is
   use Tables_Maps, Field_Lists, Foreign_Refs;
   use Foreign_Keys, Pair_Lists;

   package String_Lists is new Ada.Containers.Indefinite_Doubly_Linked_Lists
     (String);
   use String_Lists;

   procedure Parse_Table
     (Self        : DB_Schema_IO'Class;
      Table       : Table_Description;
      Attributes  : in out Field_List);
   --  Get the attributes of the specified table

   procedure Mark_FK_As_Ambiguous
     (Table     : in out Table_Description;
      Foreign   : Table_Description;
      Ambiguous : out Boolean);
   --  Mark all foreign keys from Table to Foreign as ambiguous (ie there are
   --  multiple references to the same foreign table, so we need special care
   --  in code generation). Ambiguous is set to False if there was no such
   --  FK yet.

   function Get_To (FK : Foreign_Key; Pair : Field_Pair) return Field;
   --  Return the field this points to (possibly the primary key of another
   --  table if FK.To is unset)

   ------------
   -- Get_To --
   ------------

   function Get_To (FK : Foreign_Key; Pair : Field_Pair) return Field is
   begin
      if Pair.To = No_Field then
         return Get_PK (FK.To_Table);
      else
         return Pair.To;
      end if;
   end Get_To;

   --------
   -- Id --
   --------

   function Id (Self : Field) return Positive is
   begin
      return Self.Get.Id;
   end Id;

   ----------
   -- Name --
   ----------

   function Name (Self : Field) return String is
   begin
      return Self.Get.Name.all;
   end Name;

   -----------------
   -- Description --
   -----------------

   function Description (Self : Field) return String is
      Descr : constant GNAT.Strings.String_Access := Self.Get.Description;
   begin
      if Descr = null then
         return "";
      else
         return Descr.all;
      end if;
   end Description;

   ---------------
   -- Get_Table --
   ---------------

   function Get_Table (Self : Field) return Table_Description'Class is
   begin
      return Table_Description'
        (Tables_Ref.Get (Self.Get.Table) with null record);
   end Get_Table;

   --------------
   -- Get_Type --
   --------------

   function Get_Type (Self : Field) return Field_Type is
      D  : constant Fields_Ref.Encapsulated_Access := Self.Get;
      FK : constant Field := Self.Is_FK;
   begin
      if FK = No_Field then
         return D.Typ;
      else
         return Get_Type (FK);
      end if;
   end Get_Type;

   ----------------
   -- Set_Active --
   ----------------

   procedure Set_Active (Self : in out Field; Active : Boolean) is
   begin
      Self.Get.Active := Active;
   end Set_Active;

   ---------------
   -- Is_Active --
   ---------------

   function Is_Active (Self : Field) return Boolean is
   begin
      return Self.Get.Active;
   end Is_Active;

   -----------------
   -- Can_Be_Null --
   -----------------

   function Can_Be_Null (Self : Field) return Boolean is
   begin
      return not Self.Get.Not_Null;
   end Can_Be_Null;

   -------------
   -- Default --
   -------------

   function Default (Self : Field) return String is
      Def : constant GNAT.Strings.String_Access := Self.Get.Default;
   begin
      if Def = null then
         return "";
      else
         return Def.all;
      end if;
   end Default;

   -----------
   -- Is_PK --
   -----------

   function Is_PK (Self : Field) return Boolean is
   begin
      return Self.Get.PK;
   end Is_PK;

   ------------
   -- Get_PK --
   ------------

   function Get_PK (Self : Table_Description'Class) return Field is
      F  : Field_Lists.Cursor := TDR (Self.Get).Fields.First;
      PK : Field := No_Field;
   begin
      while Has_Element (F) loop
         if Element (F).Get.PK then
            if PK = No_Field then
               PK := Element (F);
            else
               return No_Field;  --  Primary key is a tuple
            end if;
         end if;

         Next (F);
      end loop;

      return PK;
   end Get_PK;

   -----------
   -- Is_FK --
   -----------

   function Is_FK (Self : Field) return Field is
      T : Table_Description;
      C : Foreign_Keys.Cursor;
   begin
      if Self.Get.FK then
         T := Table_Description (Get_Table (Self));
         C := TDR (T.Get).FK.First;
         while Has_Element (C) loop
            declare
               FK : constant Foreign_Refs.Encapsulated_Access :=
                 Element (C).Get;
               A : Pair_Lists.Cursor := FK.Fields.First;
               P : Field_Pair;
            begin
               while Has_Element (A) loop
                  P := Element (A);
                  if P.From = Self then
                     return Get_To (Element (C), P);
                  end if;

                  Next (A);
               end loop;
            end;

            Next (C);
         end loop;
      end if;

      return No_Field;
   end Is_FK;

   ----------
   -- Free --
   ----------

   overriding procedure Free (Self : in out Field_Description) is
   begin
      Free (Self.Name);
      Free (Self.Description);
      Free (Self.Default);
   end Free;

   --------
   -- Id --
   --------

   function Id (Self : Table_Description) return Positive is
   begin
      return TDR (Self.Get).Id;
   end Id;

   --------------
   -- Get_Kind --
   --------------

   function Get_Kind (Self : Table_Description) return Relation_Kind is
   begin
      return TDR (Self.Get).Kind;
   end Get_Kind;

   ----------
   -- Name --
   ----------

   function Name (Self : Table_Description) return String is
   begin
      return TDR (Self.Get).Name.all;
   end Name;

   --------------
   -- Row_Name --
   --------------

   function Row_Name (Self : Table_Description) return String is
      Row : constant GNAT.Strings.String_Access := TDR (Self.Get).Row;
   begin
      if Row = null then
         return TDR (Self.Get).Name.all;
      else
         return Row.all;
      end if;
   end Row_Name;

   -----------------
   -- Description --
   -----------------

   function Description (Self : Table_Description) return String is
      Descr : constant GNAT.Strings.String_Access :=
        TDR (Self.Get).Description;
   begin
      if Descr = null then
         return "";
      else
         return Descr.all;
      end if;
   end Description;

   -----------------
   -- Is_Abstract --
   -----------------

   function Is_Abstract (Self : Table_Description) return Boolean is
   begin
      return TDR (Self.Get).Is_Abstract;
   end Is_Abstract;

   ----------------
   -- Set_Active --
   ----------------

   procedure Set_Active (Self : in out Table_Description; Active : Boolean) is
   begin
      TDR (Self.Get).Active := Active;
   end Set_Active;

   ---------------
   -- Is_Active --
   ---------------

   function Is_Active (Self : Table_Description) return Boolean is
   begin
      return TDR (Self.Get).Active;
   end Is_Active;

   -----------------
   -- Super_Table --
   -----------------

   function Super_Table (Self : Table_Description) return Table_Description is
   begin
      return TDR (Self.Get).Super_Table;
   end Super_Table;

   --------------------
   -- For_Each_Field --
   --------------------

   procedure For_Each_Field
     (Self              : Table_Description;
      Callback          : access procedure (F : in out Field);
      Include_Inherited : Boolean := False)
   is
      C      : Field_Lists.Cursor := TDR (Self.Get).Fields.First;
      F      : Field;
   begin
      while Has_Element (C) loop
         F := Element (C);
         Callback (F);
         Next (C);
      end loop;

      if Include_Inherited
        and then TDR (Self.Get).Super_Table /= No_Table
      then
         For_Each_Field (Self.Super_Table, Callback, Include_Inherited);
      end if;
   end For_Each_Field;

   ---------------------
   -- Field_From_Name --
   ---------------------

   function Field_From_Name
     (Self  : Table_Description'Class; Name  : String) return Field
   is
      Result : Field := No_Field;

      procedure For_Field (F : in out Field);
      procedure For_Field (F : in out Field) is
      begin
         if F.Name = Name then
            Result := F;
         end if;
      end For_Field;

   begin
      For_Each_Field (Self, For_Field'Access, Include_Inherited => True);
      return Result;
   end Field_From_Name;

   ----------
   -- Free --
   ----------

   overriding procedure Free (Self : in out Foreign_Key_Description) is
   begin
      Free (Self.Revert_Name);
   end Free;

   ----------
   -- Free --
   ----------

   overriding procedure Free (Self : in out Table_Description_Record) is
   begin
      Free (Self.Name);
      Free (Self.Row);
      Free (Self.Description);
   end Free;

   ---------------
   -- Get_Table --
   ---------------

   function Get_Table
     (Self : DB_Schema; Name : String) return Table_Description
   is
      C : constant Tables_Maps.Cursor := Self.Tables.Find (Name);
   begin
      if C = Tables_Maps.No_Element then
         raise Invalid_Table with
           "No such table: " & Name;
      end if;

      return Element (C);
   end Get_Table;

   --------------------
   -- For_Each_Table --
   --------------------

   procedure For_Each_Table
     (Self     : DB_Schema;
      Callback : access procedure (T : in out Table_Description))
   is
      C : Tables_Maps.Cursor := Self.Tables.First;
      T : Table_Description;
   begin
      while Has_Element (C) loop
         T := Element (C);
         Callback (T);
         Next (C);
      end loop;
   end For_Each_Table;

   -----------------
   -- For_Each_FK --
   -----------------

   procedure For_Each_FK
     (Self     : Table_Description;
      Callback : access procedure
        (From, To : Field; Id : Natural; Ambiguous : Boolean))
   is
      F  : Foreign_Keys.Cursor;
      P  : Pair_Lists.Cursor;
      Id : Integer := 1;
   begin
      F := TDR (Self.Get).FK.First;
      while Has_Element (F) loop
         P := Element (F).Get.Fields.First;
         while Has_Element (P) loop
            Callback (From      => Element (P).From,
                      To        => Get_To (Element (F), Element (P)),
                      Ambiguous => Element (F).Get.Ambiguous,
                      Id        => Id);
            Next (P);
         end loop;

         Id := Id + 1;
         Next (F);
      end loop;
   end For_Each_FK;

   ------------
   -- To_SQL --
   ------------

   function To_SQL (Typ : Field_Type) return String is
   begin
      case Typ is
         when Field_Boolean => return "Boolean";
         when Field_Text    => return "Text";
         when Field_Integer => return "Integer";
         when Field_Date    => return "Date";
         when Field_Time    => return "Time";
         when Field_Float   => return "Float";
      end case;
   end To_SQL;

   --------------
   -- From_SQL --
   --------------

   function From_SQL (SQL_Type : String) return Field_Type is
      T     : constant String := To_Lower (SQL_Type);
   begin
      if T = "boolean" then
         return Field_Boolean;

      elsif T = "text"
        or else
          (T'Length >= 9 and then T (T'First .. T'First + 8) = "character")
      then
         return Field_Text;

      elsif T = "integer"
        or else T = "smallint"
        or else T = "oid"
        or else (T'Length >= 7 and then T (T'First .. T'First + 6) = "numeric")
      then
         return Field_Integer;

      elsif T = "date" then
         return Field_Date;

      elsif T = "timestamp without time zone"
        or else T = "timestamp with time zone"
        or else T = "timestamp"
      then
         return Field_Time;

      elsif T = "double precision" then
         return Field_Float;

      else
         raise Invalid_Type
           with "Cannot convert """ & T & """ to Ada";
      end if;
   end From_SQL;

   -----------------
   -- Parse_Table --
   -----------------

   procedure Parse_Table
     (Self        : DB_Schema_IO'Class;
      Table       : Table_Description;
      Attributes  : in out Field_List)
   is
      procedure On_Field
        (Name           : String;
         Typ            : String;
         Index          : Natural;
         Description    : String;
         Default_Value  : String;
         Is_Primary_Key : Boolean;
         Not_Null       : Boolean);
      --  Called when a new field is discovered

      procedure On_Field
        (Name           : String;
         Typ            : String;
         Index          : Natural;
         Description    : String;
         Default_Value  : String;
         Is_Primary_Key : Boolean;
         Not_Null       : Boolean)
      is
         Descr : Field_Description;
         Ref   : Field;
      begin
         Descr := Field_Description'
           (Weak_Refcounted with
            Name        => new String'(Name),
            Typ         => From_SQL (Typ),
            Id          => Index,
            Description => new String'(Description),
            Default     => null,
            PK          => Is_Primary_Key,
            Not_Null    => Not_Null,
            FK          => False,
            Table       => Tables_Ref.Get_Weak_Ref (Table),
            Active      => True);

         if Default_Value'Length < 8
           or else Default_Value
             (Default_Value'First .. Default_Value'First + 7)
           /= "nextval("
         then
            Descr.Default  := new String'(Default_Value);
         end if;

         Set (Ref, Descr);
         Append (Attributes, Ref);
      end On_Field;

   begin
      Foreach_Field
        (Self.DB,
         Table_Name => Table.Name,
         Callback   => On_Field'Access);
   end Parse_Table;

   -----------------
   -- Read_Schema --
   -----------------

   overriding procedure Read_Schema
     (Self : DB_Schema_IO; Schema : out DB_Schema)
   is
      T : Natural := 0;

      procedure On_Table (Name, Description : String; Kind : Relation_Kind);
      --  Called when a new table is discovered

      procedure Compute_Foreign_Keys
        (Name  : String; Table : in out Table_Description);
      --  Compute the foreign keys for a specific table

      function Field_From_Index
        (Descr     : Table_Description;
         Index     : Natural) return Field;
      --  Return the field given its index in the table. Information
      --  is extracted from All_Attrs

      --------------
      -- On_Table --
      --------------

      procedure On_Table (Name, Description : String; Kind : Relation_Kind) is
         Descr : Table_Description_Record;
         Ref   : Table_Description;
      begin
         T := T + 1;
         Descr.Id          := T;
         Descr.Kind        := Kind;
         Descr.Name        := new String'(Name);
         Descr.Row         := null;  --  Will default to Descr.Name
         Descr.Description := new String'(Description);
         Set (Ref, Descr);

         Parse_Table (Self, Ref, TDR (Ref.Get).Fields);
         Insert (Schema.Tables, Name, Ref);
      end On_Table;

      ----------------------
      -- Field_From_Index --
      ----------------------

      function Field_From_Index
        (Descr     : Table_Description;
         Index     : Natural) return Field
      is
         A : Field_Lists.Cursor := First (TDR (Descr.Get).Fields);
      begin
         while Has_Element (A) loop
            if Element (A).Id = Index then
               return Element (A);
            end if;
            Next (A);
         end loop;
         return No_Field;
      end Field_From_Index;

      --------------------------
      -- Compute_Foreign_Keys --
      --------------------------

      procedure Compute_Foreign_Keys
        (Name  : String; Table : in out Table_Description)
      is
         Prev_Index : Integer := -1;
         To_Table   : Table_Description;
         Descr      : Foreign_Key_Description;
         R          : Foreign_Key;

         procedure On_Key
           (Index             : Positive;
            Local_Attribute   : Integer;
            Foreign_Table     : String;
            Foreign_Attribute : Integer);
         --  Called for each foreign key in the table

         procedure On_Key
           (Index             : Positive;
            Local_Attribute   : Integer;
            Foreign_Table     : String;
            Foreign_Attribute : Integer)
         is
            From : Field;
         begin
            if Prev_Index /= Index then
               --  A new foreign key, as opposed to a new attribute in the same
               --  key

               if Prev_Index /= -1 then
                  Set (R, Descr);
                  Append (TDR (Table.Get).FK, R);
               end if;

               Prev_Index := Index;

               To_Table := Get_Table (Schema, Foreign_Table);
               Descr :=
                 (Refcounted with
                  To_Table        => Tables_Ref.Get_Weak_Ref (To_Table),
                  Revert_Name     => null,
                  Fields          => Pair_Lists.Empty_List,
                  Ambiguous       => False);

               Mark_FK_As_Ambiguous (Table, To_Table, Descr.Ambiguous);
            end if;

            From := Field_From_Index (Table, Local_Attribute);
            From.Get.FK := True;
            Append
              (Descr.Fields,
               Field_Pair'
                 (From => From,
                  To   => Field_From_Index (To_Table, Foreign_Attribute)));
         end On_Key;

      begin
         Foreach_Foreign_Key
           (Self.DB,
            Table_Name => Name,
            Callback   => On_Key'Access);

         if Prev_Index /= -1 then
            Set (R, Descr);
            Append (TDR (Table.Get).FK, R);
         end if;
      end Compute_Foreign_Keys;

      C : Tables_Maps.Cursor;

   begin
      Foreach_Table (Self.DB, On_Table'Access);

      C := First (Schema.Tables);
      while Has_Element (C) loop
         Update_Element (Schema.Tables, C, Compute_Foreign_Keys'Access);
         Next (C);
      end loop;
   end Read_Schema;

   --------------
   -- To_Table --
   --------------

   function To_Table (FK : Foreign_Key) return Table_Description'Class is
   begin
      return Table_Description'
        (Tables_Ref.Get (FK.Get.To_Table) with null record);
   end To_Table;

   --------------------------
   -- Mark_FK_As_Ambiguous --
   --------------------------

   procedure Mark_FK_As_Ambiguous
     (Table     : in out Table_Description;
      Foreign   : Table_Description;
      Ambiguous : out Boolean)
   is
      C     : Foreign_Keys.Cursor := First (TDR (Table.Get).FK);
      FK    : Foreign_Key;
   begin
      Ambiguous := False;

      while Has_Element (C) loop
         FK := Element (C);

         if TDR (Tables_Ref.Get (FK.Get.To_Table).Get) = TDR (Foreign.Get) then
            if not FK.Get.Ambiguous then
               FK.Get.Ambiguous := True;
               Replace_Element (TDR (Table.Get).FK, C, FK);
            end if;

            Ambiguous := True;
            return;
         end if;
         Next (C);
      end loop;
   end Mark_FK_As_Ambiguous;

   -----------------
   -- Read_Schema --
   -----------------

   overriding procedure Read_Schema
     (Self : File_Schema_IO; Schema : out DB_Schema)
   is
      Str   : GNAT.Strings.String_Access;
      T     : Natural := 0;  --  Index of the table we are creating
      First : Natural; --  Current index in Str
      Line_Number : Natural := 0;

      Fields_Per_Line : constant := 5;
      --  Maximum number of fields per line (fields are separated with |)

      type Line_Fields is new String_List (1 .. Fields_Per_Line);

      function EOL return Natural;
      --  Return the position of the next End-Of-Line character after First

      function EOW return Natural;
      --  Return the position of end-of-word starting at First

      procedure Skip_Blanks;
      --  Move First forward until it is no longer on a whitespace

      procedure Parse_Line (Result : in out Line_Fields);
      --  Split the line that starts at First into its fields.
      --  On exit, First points to the beginning of the next line

      procedure Parse_Table (Table_Def, Name : String);
      --  Parse a table description

      procedure Parse_Table_Inheritance
        (Table_Def : String; Table : in out Table_Description);
      --  Parse the description of table inheritance

      procedure Parse_FK (Name : String);
      --  Parse all foreign keys for table Name

      procedure Free (Lines : in out Line_Fields);

      ----------
      -- Free --
      ----------

      procedure Free (Lines : in out Line_Fields) is
      begin
         for R in Lines'Range loop
            Free (Lines (R));
         end loop;
      end Free;

      ----------------
      -- Parse_Line --
      ----------------

      procedure Parse_Line (Result : in out Line_Fields) is
         Index  : Natural := Result'First;
         Last, Tmp : Natural;
         Current_Line_End : constant Natural := EOL;
      begin
         pragma Assert (Str (First) = '|');
         Line_Number := Line_Number + 1;

         Free (Result);

         First := First + 1;

         while First <= Current_Line_End loop
            Skip_Blanks;  --  First now points to first non-blank char
            Last := EOW;
            Tmp := Last - 1;

            while Tmp >= First and then Str (Tmp) = ' ' loop
               Tmp := Tmp - 1;
            end loop;

            Result (Index) := new String'(Str (First .. Tmp));
            Index := Index + 1;
            exit when Index > Fields_Per_Line;

            First := Last + 1;
         end loop;

         First := Current_Line_End + 1;
      end Parse_Line;

      -----------------
      -- Skip_Blanks --
      -----------------

      procedure Skip_Blanks is
      begin
         while First <= Str'Last and then Str (First) = ' ' loop
            First := First + 1;
         end loop;
      end Skip_Blanks;

      ---------
      -- EOL --
      ---------

      function EOL return Natural is
         Last : Natural := First;
      begin
         while Last <= Str'Last and then Str (Last) /= ASCII.LF loop
            Last := Last + 1;
         end loop;
         return Last;
      end EOL;

      ---------
      -- EOW --
      ---------

      function EOW return Natural is
         Last : Natural := First;
      begin
         while Last <= Str'Last
           and then Str (Last) /= '|'
         loop
            Last := Last + 1;
         end loop;
         return Last;
      end EOW;

      -----------------------------
      -- Parse_Table_Inheritance --
      -----------------------------

      procedure Parse_Table_Inheritance
        (Table_Def : String; Table : in out Table_Description)
      is
         First : Natural := Table_Def'First;
         Last  : Natural;
      begin
         while First <= Table_Def'Last loop
            if Table_Def (First) = '(' then
               Last := First + 1;
               while Last <= Table_Def'Last loop
                  if Table_Def (Last) = ')' then
                     TDR (Table.Get).Super_Table :=
                       Get_Table (Schema, Table_Def (First + 1 .. Last - 1));
                     return;
                  end if;
                  Last := Last + 1;
               end loop;
            end if;

            First := First + 1;
         end loop;
      end Parse_Table_Inheritance;

      -----------------
      -- Parse_Table --
      -----------------

      procedure Parse_Table (Table_Def, Name : String) is
         Table : Table_Description;
         Line  : Line_Fields;
         Attr_Id : Natural := 0;
      begin
         T := T + 1;

         --  The code below might be creating table before we actually see
         --  their schema (in the case of FK to them). Reuse the prior
         --  definition if one is found.
         declare
            C : Tables_Maps.Cursor;
         begin
            C := Find (Schema.Tables, Name);
            if C = Tables_Maps.No_Element then
               Set (Table, Table_Description_Record'
                   (Weak_Refcounted with
                    Name        => new String'(Name),
                    Row         => null,
                    Kind        => Kind_Table,
                    Id          => T,
                    Description => null,
                    Fields      => Empty_Field_List,
                    Is_Abstract => False,
                    FK          => Foreign_Keys.Empty_List,
                    Active      => True,
                    Super_Table => No_Table));
            else
               Table := Element (C);
            end if;

            TDR (Table.Get).Is_Abstract := Starts_With (Table_Def, "ABSTRACT");
         end;

         Parse_Table_Inheritance (Table_Def, Table);

         while First <= Str'Last and then Str (First) = '|' loop
            Parse_Line (Result => Line);

            if Line (1).all = "FK:" then
               null;   --  Skip for now, will do in second pass

            else
               Attr_Id := Attr_Id + 1;

               declare
                  Typ       : String renames Line (2).all;
                  Tmp, Tmp2 : Natural;

                  Att : Field;
                  FKD : Foreign_Key_Description;
                  FK  : Foreign_Key;
                  To_Table : Table_Description;

               begin
                  Set (Att, Field_Description'
                         (Weak_Refcounted with
                          Name        => new String'(Line (1).all),
                          Typ         => Field_Text,
                          Id          => Attr_Id,
                          Description => new String'(Line (5).all),
                          Default     => new String'(Line (4).all),
                          PK          => Line (3).all = "PK",
                          Not_Null    =>
                            Line (3).all = "PK"
                            or else Line (3).all = "NOT NULL",
                          FK          => Typ'Length > 3
                            and then Typ (Typ'First .. Typ'First + 2) = "FK ",
                          Table       => Tables_Ref.Get_Weak_Ref (Table),
                          Active      => True));
                  Append (TDR (Table.Get).Fields, Att);

                  if Att.Get.FK then
                     Tmp := Typ'First + 3;
                     while Tmp <= Typ'Last and then Typ (Tmp) /= '(' loop
                        Tmp := Tmp + 1;
                     end loop;

                     if Tmp < Typ'Last then
                        Tmp2 := Tmp + 1;
                        while Tmp2 < Typ'Last and then Typ (Tmp2) /= ')' loop
                           Tmp2 := Tmp2 + 1;
                        end loop;
                     else
                        Tmp2 := Typ'Last;
                     end if;

                     declare
                        To : constant String :=
                          Trim (Typ (Typ'First + 3 .. Tmp - 1), Both);
                     begin
                        if To = Name then
                           To_Table := Table;
                        else
                           To_Table := Get_Table (Schema, To);
                        end if;

                     exception
                        when Invalid_Table =>
                           --  The table might be declared later on
                           Set (To_Table, Table_Description_Record'
                                  (Weak_Refcounted with
                                   Name   => new String'(To),
                                   others => <>));
                           Include (Schema.Tables, To, To_Table);
                     end;

                     FKD := Foreign_Key_Description'
                       (Refcounted with
                        To_Table    => Tables_Ref.Get_Weak_Ref (To_Table),
                        Revert_Name => new String'(Typ (Tmp + 1 .. Tmp2 - 1)),
                        Fields      => Pair_Lists.Empty_List,
                        Ambiguous   => False);
                     Mark_FK_As_Ambiguous (Table, To_Table, FKD.Ambiguous);

                     Append (FKD.Fields,
                             Field_Pair'
                               (From => Att,
                                To   => No_Field));   --  To primary key

                     Set (FK, FKD);
                     Append (TDR (Table.Get).FK, FK);

                     Att.Get.FK := True;

                  else
                     Att.Get.Typ := From_SQL (Typ);
                  end if;
               end;
            end if;
         end loop;

         Free (Line);
         Include (Schema.Tables, Name, Table);
      end Parse_Table;

      --------------
      -- Parse_FK --
      --------------

      procedure Parse_FK (Name : String) is
         Curs  : constant Tables_Maps.Cursor := Schema.Tables.Find (Name);
         From_Table : Table_Description := Element (Curs);
         To_Table : Table_Description;
         FK    : Foreign_Key;
         Line  : Line_Fields;
      begin
         while First <= Str'Last and then Str (First) = '|' loop
            Parse_Line (Result => Line);

            if Line (1).all = "FK:" then
               To_Table := Get_Table (Schema, Line (2).all);
               Set (FK, Foreign_Key_Description'
                    (Refcounted with
                     To_Table        => Tables_Ref.Get_Weak_Ref (To_Table),
                     Revert_Name     => null,
                     Ambiguous       => False,
                     Fields          => Pair_Lists.Empty_List));
               Mark_FK_As_Ambiguous (From_Table, To_Table, FK.Get.Ambiguous);

               declare
                  From : String renames Line (3).all;
                  To   : String renames Line (4).all;
                  First, Tmp : Natural;
                  C    : Pair_Lists.Cursor;
               begin
                  First := From'First;
                  while First <= From'Last loop
                     Tmp := First + 1;
                     while Tmp <= From'Last and then From (Tmp) /= ' ' loop
                        Tmp := Tmp + 1;
                     end loop;

                     Append (FK.Get.Fields,
                             (From => From_Table.Field_From_Name
                                        (From (First .. Tmp - 1)),
                              To   => No_Field));  --  Will be set later
                     First := Tmp + 1;
                     Skip_Blanks;
                  end loop;

                  C := FK.Get.Fields.First;

                  First := To'First;
                  while First <= To'Last loop
                     Tmp := First + 1;
                     while Tmp <= To'Last and then To (Tmp) /= ' ' loop
                        Tmp := Tmp + 1;
                     end loop;

                     Replace_Element
                       (FK.Get.Fields, C,
                        (From => Element (C).From,
                         To   => To_Table.Field_From_Name
                                   (To (First .. Tmp - 1))));
                     First := Tmp + 1;
                     Skip_Blanks;
                  end loop;
               end;

               Append (TDR (From_Table.Get).FK, FK);
            end if;
         end loop;

         Free (Line);
         Replace_Element (Schema.Tables, Curs, From_Table);
      end Parse_FK;

      Line : Line_Fields;
      type Parse_Mode is (Parsing_Table, Parsing_FK);

   begin
      Str := Read_Whole_File (To_String (Self.Filename));

      for Mode in Parse_Mode loop
         First := Str'First;
         Line_Number := 0;

         while First <= Str'Last loop
            if Str (First) = '|' then
               Parse_Line (Result => Line);

               if Starts_With (Line (1).all, "ABSTRACT TABLE")
                 or else Starts_With (Line (1).all, "TABLE")
               then
                  case Mode is
                     when Parsing_Table =>
                        Parse_Table (Line (1).all, Line (2).all);
                     when Parsing_FK    =>
                        Parse_FK (Line (2).all);
                  end case;
               end if;
            else
               First := EOL + 1;
            end if;
         end loop;
      end loop;

      Free (Line);
      Free (Str);

   exception
      when E : Invalid_Type =>
         Free (Line);
         Put_Line (Standard_Error,
                   To_String (Self.Filename)
                   & ":" & Image (Line_Number, Min_Width => 1) & " "
                   & Exception_Message (E));
         raise;

      when Name_Error =>
         Put_Line ("Could not open " & To_String (Self.Filename));
   end Read_Schema;

   ------------------
   -- Write_Schema --
   ------------------

   overriding procedure Write_Schema
     (Self : DB_Schema_IO; Schema : DB_Schema)
   is
      Indexes : String_Lists.List;
      --  Statements to execute to create the indexes

      procedure For_Table (Table : in out Table_Description);
      --  Process a table

      ---------------
      -- For_Table --
      ---------------

      procedure For_Table (Table : in out Table_Description) is
         SQL : Unbounded_String;
         --  The statement to execute

         Is_First_Attribute : Boolean := True;

         procedure Print_PK (F : in out Field);
         procedure Print_FK (Table : Table_Description);
         procedure Add_Field (F : in out Field);

         procedure Add_Field (F : in out Field) is
         begin
            if not Is_First_Attribute then
               Append (SQL, "," & ASCII.LF);
            end if;
            Is_First_Attribute := False;

            Append (SQL, "   " & F.Name & " " & To_SQL (Get_Type (F)));

            if not F.Can_Be_Null then
               Append (SQL, " NOT NULL");
            end if;

            if F.Default /= "" then
               Append (SQL, " DEFAULT '" & F.Default & "'");
            end if;
         end Add_Field;

         procedure Print_PK (F : in out Field) is
         begin
            if F.Is_PK then
               Append (SQL, ", PRIMARY KEY (" & F.Name & ")");
            end if;
         end Print_PK;

         procedure Print_FK (Table : Table_Description) is
            C : Foreign_Keys.Cursor := TDR (Table.Get).FK.First;
            F : Foreign_Refs.Encapsulated_Access;
            P : Pair_Lists.Cursor;
            Is_First : Boolean;
         begin
            while Has_Element (C) loop
               F := Element (C).Get;

               Append (SQL, ", FOREIGN KEY (");

               Is_First := True;
               P := F.Fields.First;

               while Has_Element (P) loop
                  if not Is_First then
                     Append (SQL, ",");
                  end if;
                  Is_First := False;
                  Append (SQL, Element (P).From.Name);
                  Next (P);
               end loop;

               Append
                 (SQL, ") REFERENCES " & Element (C).To_Table.Name & " (");

               Is_First := True;
               P := F.Fields.First;
               while Has_Element (P) loop
                  if not Is_First then
                     Append (SQL, ",");
                  end if;
                  Is_First := False;

                  if Element (P).To = No_Field then
                     Append (SQL, Element (C).To_Table.Get_PK.Name);
                  else
                     Append (SQL, Element (P).To.Name);
                  end if;

                  Next (P);
               end loop;

               Append (SQL, ")");

               if Length (F.Fields) = 1 then
                  --  Create indexes for the reverse relationships, since
                  --  it is likely the user will want to use them a lot
                  --  anyway
                  Append (Indexes,
                          "CREATE INDEX """
                          & Table.Name & "_"
                          & Element (F.Fields.First).From.Name
                          & """ ON """
                          & Table.Name & """ ("""
                          & Element (F.Fields.First).From.Name
                          & """)");
               end if;

               Next (C);
            end loop;
         end Print_FK;

      begin
         if not Table.Is_Abstract then
            case Table.Get_Kind is
               when Kind_Table =>
                  Append (SQL, "CREATE TABLE " & Table.Name & " (");
                  For_Each_Field
                    (Table, Add_Field'Access, Include_Inherited => True);
                  For_Each_Field (Table, Print_PK'Access, True);
                  Print_FK (Table);
                  Append (SQL, ")");

               when Kind_View  =>
                  null;
            end case;
         end if;

         if Self.DB = null then
            Put_Line (To_String (SQL) & ";");
         else
            Execute (Self.DB, To_String (SQL));
         end if;
      end For_Table;

      S  : String_Lists.Cursor;

   begin
      For_Each_Table (Schema, For_Table'Access);

      S := First (Indexes);
      while Has_Element (S) loop
         if Self.DB = null then
            Put_Line (Element (S) & ";");
         else
            Execute (Self.DB, Element (S));
         end if;

         Next (S);
      end loop;

      if Self.DB /= null then
         Commit_Or_Rollback (Self.DB);
      end if;
   end Write_Schema;

   ------------------
   -- Write_Schema --
   ------------------

   overriding procedure Write_Schema
     (Self : File_Schema_IO; Schema : DB_Schema)
   is
      To_File : File_Type;

      Not_Null : constant String := "NOT NULL";
      Column_Widths : array (1 .. 4) of Natural;
      --  The maximum width of all columns

      function SQL_Type (Attr : Field) return String;
      --  Return the type to use for Attr. This includes foreign keys when
      --  appropriate

      procedure For_Table (Table : in out Table_Description);
      --  Process a table

      procedure For_Field (F : in out Field);
      --  Process a field

      --------------
      -- SQL_Type --
      --------------

      function SQL_Type (Attr : Field) return String is
         FK : constant Field := Attr.Is_FK;
      begin
         if FK = No_Field then
            return To_SQL (Attr.Get_Type);
         else
            return "FK " & FK.Get_Table.Name;
         end if;
      end SQL_Type;

      ---------------
      -- For_Field --
      ---------------

      procedure For_Field (F : in out Field) is
         Name    : constant String := F.Name;
         Default : constant String := F.Default;
      begin
         Ada.Text_IO.Put ("|" & Name
           & (1 .. Column_Widths (1) - Name'Length => ' ') & "|");

         declare
            Typ : constant String := SQL_Type (F);
         begin
            Ada.Text_IO.Put
              (Typ & (1 .. Column_Widths (2) - Typ'Length => ' ') & "|");
         end;

         if F.Is_PK then
            Ada.Text_IO.Put ("PK      ");
         elsif not F.Can_Be_Null then
            Ada.Text_IO.Put (Not_Null);
         else
            Ada.Text_IO.Put ("        ");
         end if;

         Ada.Text_IO.Put_Line
           ("|" & Default & (1 .. Column_Widths (4) - Default'Length => ' ')
            & "|"
            & Translate (F.Description,
                         Mapping => To_Mapping ("" & ASCII.LF, " ")) & "|");
      end For_Field;

      ---------------
      -- For_Table --
      ---------------

      procedure For_Table (Table : in out Table_Description) is
         A  : Field_Lists.Cursor;
         F  : Foreign_Keys.Cursor;
         FK : Foreign_Refs.Encapsulated_Access;
         P  : Pair_Lists.Cursor;
      begin
         --  Compute widths
         --  Minimum size of column 1 is 5 (for "TABLE")
         Column_Widths := (1 => 5, 2 => 0, 3 => Not_Null'Length, 4 => 0);
         A := First (TDR (Table.Get).Fields);
         while Has_Element (A) loop
            Column_Widths (1) := Integer'Max
              (Column_Widths (1), Element (A).Name'Length);
            Column_Widths (2) := Integer'Max
              (Column_Widths (2), SQL_Type (Element (A))'Length);
            Column_Widths (4) := Integer'Max
              (Column_Widths (4), Element (A).Default'Length);
            Next (A);
         end loop;

         case Table.Get_Kind is
            when Kind_Table =>
               Put_Line
                 ("|TABLE" & (1 .. Column_Widths (1) - 5 => ' ')
                  & "| " & Table.Name);
            when Kind_View  =>
               Put_Line
                 ("|VIEW" & (1 .. Column_Widths (1) - 4 => ' ')
                  & "| " & Table.Name);
         end case;

         For_Each_Field (Table, For_Field'Access, True);

         F := TDR (Table.Get).FK.First;
         while Has_Element (F) loop
            FK := Element (F).Get;

            if Length (FK.Fields) > 1 then
               Put ("| FK: | " & Element (F).To_Table.Name & " | ");

               P := FK.Fields.First;
               while Has_Element (P) loop
                  Put (Element (P).From.Name & " ");
                  Next (P);
               end loop;

               Put (" | ");

               P := FK.Fields.First;
               while Has_Element (P) loop
                  Put (Element (P).To.Name & " ");
                  Next (P);
               end loop;

               Put_Line (" |");
            end if;

            Next (F);
         end loop;

         Ada.Text_IO.New_Line;
      end For_Table;

   begin
      if Self.Filename /= "-" then
         Create (To_File, Out_File, To_String (Self.Filename));
         Set_Output (To_File);
      end if;

      For_Each_Table (Schema, For_Table'Access);

      if Self.Filename /= "-" then
         Set_Output (Standard_Output);
         Close (To_File);
      end if;
   end Write_Schema;

end GNATCOLL.SQL.Inspect;