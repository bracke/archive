with Ada.Characters.Handling;
with Ada.Containers;
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

   function Matches
     (Item   : Archive.Archives.Entries.Archive_Entry;
      Filter : String)
      return Boolean
   is
      Name : constant String := Lower (To_String (Item.Display_Name));
   begin
      return Filter = "" or else Ada.Strings.Fixed.Index (Name, Filter) > 0;
   end Matches;

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

      function Before
        (Left_Id  : Archive.Types.Entry_Id;
         Right_Id : Archive.Types.Entry_Id)
         return Boolean
      is
         Left  : constant Archive.Archives.Entries.Archive_Entry :=
           Archive.Archives.Index.Entry_For (Index, Left_Id);
         Right : constant Archive.Archives.Entries.Archive_Entry :=
           Archive.Archives.Index.Entry_For (Index, Right_Id);
         Raw   : Boolean := False;
      begin
         if Request.Directories_First
           and then (Left.Kind = Archive.Archives.Entries.Directory)
             /= (Right.Kind = Archive.Archives.Entries.Directory)
         then
            return Left.Kind = Archive.Archives.Entries.Directory;
         end if;

         case Request.Field is
            when Sort_By_Name =>
               Raw := Lower (To_String (Left.Display_Name)) < Lower (To_String (Right.Display_Name));
            when Sort_By_Kind =>
               Raw := Archive.Archives.Entries.Entry_Kind'Pos (Left.Kind)
                 < Archive.Archives.Entries.Entry_Kind'Pos (Right.Kind);
            when Sort_By_Uncompressed_Size =>
               Raw := Size_Value (Left.Uncompressed) < Size_Value (Right.Uncompressed);
            when Sort_By_Compressed_Size =>
               Raw := Size_Value (Left.Compressed) < Size_Value (Right.Compressed);
            when Sort_By_Archive_Order =>
               Raw := Left.Ordinal < Right.Ordinal;
         end case;

         if not Raw then
            case Request.Field is
               when Sort_By_Name =>
                  if Lower (To_String (Left.Display_Name)) = Lower (To_String (Right.Display_Name)) then
                     Raw := Left.Ordinal < Right.Ordinal or else
                       (Left.Ordinal = Right.Ordinal and then Left.Id < Right.Id);
                  end if;
               when Sort_By_Kind =>
                  if Left.Kind = Right.Kind then
                     Raw := Left.Ordinal < Right.Ordinal or else
                       (Left.Ordinal = Right.Ordinal and then Left.Id < Right.Id);
                  end if;
               when Sort_By_Uncompressed_Size =>
                  if Size_Value (Left.Uncompressed) = Size_Value (Right.Uncompressed) then
                     Raw := Left.Ordinal < Right.Ordinal or else
                       (Left.Ordinal = Right.Ordinal and then Left.Id < Right.Id);
                  end if;
               when Sort_By_Compressed_Size =>
                  if Size_Value (Left.Compressed) = Size_Value (Right.Compressed) then
                     Raw := Left.Ordinal < Right.Ordinal or else
                       (Left.Ordinal = Right.Ordinal and then Left.Id < Right.Id);
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
         return not Raw
           and then Left.Id /= Right.Id;
      end Before;

      package Sorting is new Archive.Types.Entry_Id_Vectors.Generic_Sorting ("<" => Before);

      Children : constant Archive.Types.Entry_Id_Vectors.Vector :=
        Archive.Archives.Index.Children (Index, Request.Parent);
   begin
      for Id of Children loop
         declare
            Item : constant Archive.Archives.Entries.Archive_Entry :=
              Archive.Archives.Index.Entry_For (Index, Id);
         begin
            if Matches (Item, Filter) then
               if Result.Entries.Length < Ada.Containers.Count_Type (Request.Limit) then
                  Result.Entries.Append (Id);
               else
                  Result.Truncated := True;
               end if;
            end if;
         end;
      end loop;

      Sorting.Sort (Result.Entries);
      return Result;
   end Project;
end Archive.View_Snapshots;
