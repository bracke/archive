with Ada.Characters.Handling;
with Ada.Containers;
with Ada.Containers.Vectors;
with Ada.Strings.Fixed;
with Ada.Strings.Unbounded;

with Archive.Archives.Entries;

package body Archive.View_Snapshots is
   use Ada.Strings.Unbounded;
   use type Ada.Containers.Count_Type;
   use type Archive.Archives.Entries.Entry_Kind;
   use type Archive.Types.Entry_Id;
   use type Archive.Types.Uncompressed_Size;
   use type Archive.Types.Archive_Ordinal;

   function Lower (Value : String) return String is
      Result : String := Value;
   begin
      for C of Result loop
         C := Ada.Characters.Handling.To_Lower (C);
      end loop;
      return Result;
   end Lower;

   function Size_Value (Value : Archive.Types.Optional_Size) return Archive.Types.Uncompressed_Size is
   begin
      if Value.Present then
         return Value.Value;
      end if;
      return 0;
   end Size_Value;

   function Project
     (Index   : Archive.Archives.Index.Archive_Index;
      Request : Projection_Request)
      return Projection_Result
   is
      Result : Projection_Result;
      Filter : constant String := Lower (To_String (Request.Filter_Text));

      --  Each matching child is decorated once with the lowercased name and the
      --  numeric sort keys the comparison needs, so the sort neither re-resolves
      --  the entry (Entry_For) nor re-lowercases its name on every comparison --
      --  turning an O(children^2 log children) projection into O(children).
      type Sort_Row is record
         Id           : Archive.Types.Entry_Id;
         Is_Directory : Boolean;
         Name_Lower   : Unbounded_String;
         Kind_Pos     : Natural;
         Uncompressed : Archive.Types.Uncompressed_Size;
         Compressed   : Archive.Types.Uncompressed_Size;
         Ordinal      : Archive.Types.Archive_Ordinal;
      end record;

      package Row_Vectors is new Ada.Containers.Vectors
        (Index_Type => Positive, Element_Type => Sort_Row);

      Rows : Row_Vectors.Vector;

      --  Equal primary keys fall back to archive order, then id -- exactly the
      --  tiebreak the previous per-field comparator applied.
      function Tiebreak (Left, Right : Sort_Row) return Boolean is
        (Left.Ordinal < Right.Ordinal
         or else (Left.Ordinal = Right.Ordinal and then Left.Id < Right.Id));

      function Before (Left, Right : Sort_Row) return Boolean is
         Raw : Boolean := False;
      begin
         if Request.Directories_First
           and then Left.Is_Directory /= Right.Is_Directory
         then
            return Left.Is_Directory;
         end if;

         case Request.Field is
            when Sort_By_Name =>
               Raw := Left.Name_Lower < Right.Name_Lower;
            when Sort_By_Kind =>
               Raw := Left.Kind_Pos < Right.Kind_Pos;
            when Sort_By_Uncompressed_Size =>
               Raw := Left.Uncompressed < Right.Uncompressed;
            when Sort_By_Compressed_Size =>
               Raw := Left.Compressed < Right.Compressed;
            when Sort_By_Archive_Order =>
               Raw := Left.Ordinal < Right.Ordinal;
         end case;

         if not Raw then
            case Request.Field is
               when Sort_By_Name =>
                  if Left.Name_Lower = Right.Name_Lower then
                     Raw := Tiebreak (Left, Right);
                  end if;
               when Sort_By_Kind =>
                  if Left.Kind_Pos = Right.Kind_Pos then
                     Raw := Tiebreak (Left, Right);
                  end if;
               when Sort_By_Uncompressed_Size =>
                  if Left.Uncompressed = Right.Uncompressed then
                     Raw := Tiebreak (Left, Right);
                  end if;
               when Sort_By_Compressed_Size =>
                  if Left.Compressed = Right.Compressed then
                     Raw := Tiebreak (Left, Right);
                  end if;
               when Sort_By_Archive_Order =>
                  if Left.Ordinal = Right.Ordinal then
                     Raw := Left.Id < Right.Id;
                  end if;
            end case;
         end if;

         if Request.Direction = Ascending then
            return Raw;
         end if;
         return not Raw and then Left.Id /= Right.Id;
      end Before;

      package Sorting is new Row_Vectors.Generic_Sorting ("<" => Before);

      Children : constant Archive.Types.Entry_Id_Vectors.Vector :=
        Archive.Archives.Index.Children (Index, Request.Parent);
   begin
      for Id of Children loop
         declare
            Item : constant Archive.Archives.Entries.Archive_Entry :=
              Archive.Archives.Index.Entry_For (Index, Id);
            Name_Lower : constant String := Lower (To_String (Item.Display_Name));
         begin
            if Filter = "" or else Ada.Strings.Fixed.Index (Name_Lower, Filter) > 0 then
               if Rows.Length < Ada.Containers.Count_Type (Request.Limit) then
                  Rows.Append
                    (Sort_Row'
                       (Id           => Id,
                        Is_Directory =>
                          Item.Kind = Archive.Archives.Entries.Directory,
                        Name_Lower   => To_Unbounded_String (Name_Lower),
                        Kind_Pos     =>
                          Archive.Archives.Entries.Entry_Kind'Pos (Item.Kind),
                        Uncompressed => Size_Value (Item.Uncompressed),
                        Compressed   => Size_Value (Item.Compressed),
                        Ordinal      => Item.Ordinal));
               else
                  Result.Truncated := True;
               end if;
            end if;
         end;
      end loop;

      Sorting.Sort (Rows);
      for Row of Rows loop
         Result.Entries.Append (Row.Id);
      end loop;
      return Result;
   end Project;
end Archive.View_Snapshots;
