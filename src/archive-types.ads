with Ada.Containers.Vectors;
with Ada.Strings.Unbounded;
with Interfaces;

package Archive.Types is
   use type Ada.Strings.Unbounded.Unbounded_String;

   subtype UString is Ada.Strings.Unbounded.Unbounded_String;

   package String_Vectors is new Ada.Containers.Vectors
     (Index_Type   => Positive,
      Element_Type => UString);

   type Entry_Id is new Interfaces.Unsigned_64;
   No_Entry : constant Entry_Id := 0;

   package Entry_Id_Vectors is new Ada.Containers.Vectors
     (Index_Type   => Positive,
      Element_Type => Entry_Id);

   type Archive_Ordinal is new Interfaces.Unsigned_64;
   type Generation_Id is new Interfaces.Unsigned_64;
   No_Generation : constant Generation_Id := 0;

   type Source_Offset is new Interfaces.Unsigned_64;
   type Compressed_Size is new Interfaces.Unsigned_64;
   type Uncompressed_Size is new Interfaces.Unsigned_64;
   type CRC32_Value is new Interfaces.Unsigned_32;

   type Optional_Offset (Present : Boolean := False) is record
      case Present is
         when True =>
            Value : Source_Offset := 0;
         when False =>
            null;
      end case;
   end record;

   type Optional_CRC32 (Present : Boolean := False) is record
      case Present is
         when True =>
            Value : CRC32_Value := 0;
         when False =>
            null;
      end case;
   end record;

   type Optional_Size (Present : Boolean := False) is record
      case Present is
         when True =>
            Value : Uncompressed_Size := 0;
         when False =>
            null;
      end case;
   end record;

   type View_Mode is (Grid_View, Compact_View, Details_View);
end Archive.Types;
