with Ada.Strings.Unbounded;
with Interfaces;

package body Archive.Preview is
   use Ada.Strings.Unbounded;
   use type Archive.Archives.Entries.Entry_Kind;
   use type Archive.Archives.Entries.Integrity_State;
   use type Archive.Archives.Errors.Error_Code;
   use type Zlib.Byte;

   function Is_Text_Byte (Byte : Zlib.Byte) return Boolean is
   begin
      return Byte = 9 or else Byte = 10 or else Byte = 13
        or else (Byte >= 32 and then Byte < 127);
   end Is_Text_Byte;

   function Looks_Text (Bytes : Zlib.Byte_Array; Count : Natural) return Boolean is
   begin
      for Index in 1 .. Count loop
         if not Is_Text_Byte (Bytes (Bytes'First + Index - 1)) then
            return False;
         end if;
      end loop;
      return True;
   end Looks_Text;

   function Hex_Digit (Value : Natural) return Character is
   begin
      if Value < 10 then
         return Character'Val (Character'Pos ('0') + Value);
      else
         return Character'Val (Character'Pos ('A') + Value - 10);
      end if;
   end Hex_Digit;

   function Image_Trimmed (Value : Natural) return String is
      Raw : constant String := Natural'Image (Value);
   begin
      if Raw'Length > 0 and then Raw (Raw'First) = ' ' then
         return Raw (Raw'First + 1 .. Raw'Last);
      end if;
      return Raw;
   end Image_Trimmed;

   function U32_BE (Bytes : Zlib.Byte_Array; Offset : Natural) return Natural is
   begin
      return Natural (Bytes (Bytes'First + Offset)) * 16#01_00_00_00#
        + Natural (Bytes (Bytes'First + Offset + 1)) * 16#00_01_00_00#
        + Natural (Bytes (Bytes'First + Offset + 2)) * 16#00_00_01_00#
        + Natural (Bytes (Bytes'First + Offset + 3));
   end U32_BE;

   function U16_LE (Bytes : Zlib.Byte_Array; Offset : Natural) return Natural is
   begin
      return Natural (Bytes (Bytes'First + Offset))
        + Natural (Bytes (Bytes'First + Offset + 1)) * 16#100#;
   end U16_LE;

   function Looks_PNG (Bytes : Zlib.Byte_Array) return Boolean is
   begin
      return Bytes'Length >= 24
        and then Bytes (Bytes'First) = 16#89#
        and then Bytes (Bytes'First + 1) = Zlib.Byte (Character'Pos ('P'))
        and then Bytes (Bytes'First + 2) = Zlib.Byte (Character'Pos ('N'))
        and then Bytes (Bytes'First + 3) = Zlib.Byte (Character'Pos ('G'));
   end Looks_PNG;

   function Looks_GIF (Bytes : Zlib.Byte_Array) return Boolean is
   begin
      return Bytes'Length >= 10
        and then Bytes (Bytes'First) = Zlib.Byte (Character'Pos ('G'))
        and then Bytes (Bytes'First + 1) = Zlib.Byte (Character'Pos ('I'))
        and then Bytes (Bytes'First + 2) = Zlib.Byte (Character'Pos ('F'));
   end Looks_GIF;

   function Looks_JPEG (Bytes : Zlib.Byte_Array) return Boolean is
   begin
      return Bytes'Length >= 3
        and then Bytes (Bytes'First) = 16#FF#
        and then Bytes (Bytes'First + 1) = 16#D8#
        and then Bytes (Bytes'First + 2) = 16#FF#;
   end Looks_JPEG;

   function Image_Summary
     (Bytes      : Zlib.Byte_Array;
      Bytes_Used : Natural)
      return String
   is
   begin
      if Looks_PNG (Bytes) then
         return "image.kind=png;image.width=" & Image_Trimmed (U32_BE (Bytes, 16))
           & ";image.height=" & Image_Trimmed (U32_BE (Bytes, 20))
           & ";preview.bytes=" & Image_Trimmed (Bytes_Used);
      elsif Looks_GIF (Bytes) then
         return "image.kind=gif;image.width=" & Image_Trimmed (U16_LE (Bytes, 6))
           & ";image.height=" & Image_Trimmed (U16_LE (Bytes, 8))
           & ";preview.bytes=" & Image_Trimmed (Bytes_Used);
      else
         return "image.kind=jpeg;preview.bytes=" & Image_Trimmed (Bytes_Used);
      end if;
   end Image_Summary;

   function Is_Image (Bytes : Zlib.Byte_Array) return Boolean is
   begin
      return Looks_PNG (Bytes) or else Looks_GIF (Bytes) or else Looks_JPEG (Bytes);
   end Is_Image;

   function Generate_Buffer
     (Bytes  : Zlib.Byte_Array;
      Limits : Preview_Limits)
      return Preview_Result
   is
      Input_Limit : constant Natural := Natural'Min (Bytes'Length, Limits.Max_Input_Bytes);
      Result      : Preview_Result;
   begin
      if Bytes'Length = 0 or else Input_Limit = 0 then
         Result.Kind := Empty_Preview;
         return Result;
      end if;

      if Is_Image (Bytes) then
         Result.Kind := Image_Preview;
         Result.Bytes_Used := Input_Limit;
         Result.Text := To_Unbounded_String (Image_Summary (Bytes, Input_Limit));
         Result.Truncated := Bytes'Length > Input_Limit;
         return Result;
      end if;

      if Looks_Text (Bytes, Input_Limit) then
         Result.Kind := Text_Preview;
         Result.Bytes_Used := Natural'Min (Input_Limit, Limits.Max_Text_Chars);
         for Index in 1 .. Result.Bytes_Used loop
            Append (Result.Text, Character'Val (Bytes (Bytes'First + Index - 1)));
         end loop;
         Result.Truncated := Bytes'Length > Result.Bytes_Used;
         return Result;
      end if;

      Result.Kind := Hex_Preview;
      Result.Bytes_Used := Natural'Min (Input_Limit, Limits.Max_Hex_Bytes);
      for Index in 1 .. Result.Bytes_Used loop
         declare
            Value : constant Natural := Natural (Bytes (Bytes'First + Index - 1));
         begin
            if Index > 1 then
               Append (Result.Text, " ");
            end if;
            Append (Result.Text, Hex_Digit (Value / 16));
            Append (Result.Text, Hex_Digit (Value mod 16));
         end;
      end loop;
      Result.Truncated := Bytes'Length > Result.Bytes_Used;
      return Result;
   end Generate_Buffer;

   procedure Initialize
     (Accumulator : in out Preview_Accumulator;
      Limits      : Preview_Limits)
   is
   begin
      Accumulator.Limits := Limits;
      Accumulator.Total := 0;
      Accumulator.Text_Chars := 0;
      Accumulator.Hex_Bytes := 0;
      Accumulator.Header_Length := 0;
      Accumulator.All_Text := True;
      Accumulator.Hit_Limit := False;
      Accumulator.Text := Null_Unbounded_String;
      Accumulator.Hex := Null_Unbounded_String;
   end Initialize;

   procedure Append
     (Accumulator : in out Preview_Accumulator;
      Bytes       : Zlib.Byte_Array;
      Continue    : in out Boolean)
   is
      Value : Natural;
   begin
      Continue := True;
      if Bytes'Length = 0 then
         return;
      end if;

      for Index in Bytes'Range loop
         exit when Accumulator.Total >= Accumulator.Limits.Max_Input_Bytes;

         Accumulator.Total := Accumulator.Total + 1;
         Value := Natural (Bytes (Index));

         if Accumulator.Header_Length < Accumulator.Header'Length then
            Accumulator.Header_Length := Accumulator.Header_Length + 1;
            Accumulator.Header (Accumulator.Header_Length) := Bytes (Index);
         end if;

         if Accumulator.Hex_Bytes < Accumulator.Limits.Max_Hex_Bytes then
            Accumulator.Hex_Bytes := Accumulator.Hex_Bytes + 1;
            if Accumulator.Hex_Bytes > 1 then
               Append (Accumulator.Hex, " ");
            end if;
            Append (Accumulator.Hex, Hex_Digit (Value / 16));
            Append (Accumulator.Hex, Hex_Digit (Value mod 16));
         end if;

         if Accumulator.All_Text then
            if Is_Text_Byte (Bytes (Index)) then
               if Accumulator.Text_Chars < Accumulator.Limits.Max_Text_Chars then
                  Accumulator.Text_Chars := Accumulator.Text_Chars + 1;
                  Append (Accumulator.Text, Character'Val (Bytes (Index)));
               end if;
            else
               Accumulator.All_Text := False;
            end if;
         end if;
      end loop;

      if Accumulator.Total >= Accumulator.Limits.Max_Input_Bytes then
         Accumulator.Hit_Limit := True;
         Continue := False;
      end if;
   end Append;

   function Finish
     (Accumulator : Preview_Accumulator)
      return Preview_Result
   is
      Result : Preview_Result;
   begin
      if Accumulator.Total = 0 then
         Result.Kind := Empty_Preview;
         return Result;
      end if;

      if Is_Image (Accumulator.Header (1 .. Accumulator.Header_Length)) then
         Result.Kind := Image_Preview;
         Result.Bytes_Used := Accumulator.Header_Length;
         Result.Text :=
           To_Unbounded_String
             (Image_Summary
                (Accumulator.Header (1 .. Accumulator.Header_Length),
                 Accumulator.Total));
         Result.Truncated := Accumulator.Hit_Limit;
      elsif Accumulator.All_Text then
         Result.Kind := Text_Preview;
         Result.Bytes_Used := Accumulator.Text_Chars;
         Result.Text := Accumulator.Text;
         Result.Truncated := Accumulator.Hit_Limit
           or else Accumulator.Total > Accumulator.Text_Chars;
      else
         Result.Kind := Hex_Preview;
         Result.Bytes_Used := Accumulator.Hex_Bytes;
         Result.Text := Accumulator.Hex;
         Result.Truncated := Accumulator.Hit_Limit
           or else Accumulator.Total > Accumulator.Hex_Bytes;
      end if;
      return Result;
   end Finish;

   function Generate_Entry_Metadata
     (Item      : Archive.Archives.Entries.Archive_Entry;
      Status    : Archive.Archives.Errors.Error_Code := Archive.Archives.Errors.Ok;
      Integrity : Archive.Archives.Entries.Integrity_State :=
        Archive.Archives.Entries.Verified)
      return Preview_Result
   is
      Result : Preview_Result;
   begin
      if Status /= Archive.Archives.Errors.Ok
        or else Integrity = Archive.Archives.Entries.Failed
      then
         Result.Kind := Untrusted_Preview;
         Result.Trusted := False;
         Result.Text := To_Unbounded_String
           ("preview.trust=failed;preview.status="
            & Archive.Archives.Errors.Error_Code'Image (Status)
            & ";preview.integrity="
            & Archive.Archives.Entries.Integrity_State'Image (Integrity));
         return Result;
      end if;

      case Item.Kind is
         when Archive.Archives.Entries.Directory =>
            Result.Kind := Directory_Preview;
            Result.Text := To_Unbounded_String
              ("entry.kind=directory;entry.path="
               & To_String (Item.Original_Path));
            Result.Trusted := True;
            return Result;

         when Archive.Archives.Entries.Symbolic_Link
            | Archive.Archives.Entries.Hard_Link =>
            Result.Kind := Link_Preview;
            Result.Text := To_Unbounded_String
              ("entry.kind="
               & Archive.Archives.Entries.Entry_Kind'Image (Item.Kind)
               & ";entry.path=" & To_String (Item.Original_Path)
               & ";entry.link_target=" & To_String (Item.Link_Target));
            Result.Trusted := True;
            return Result;

         when Archive.Archives.Entries.Metadata_Record =>
            Result.Kind := Metadata_Preview;
            Result.Text := To_Unbounded_String
              ("entry.kind=metadata;entry.path=" & To_String (Item.Original_Path)
               & ";entry.metadata=" & To_String (Item.Format_Metadata));
            Result.Trusted := True;
            return Result;

         when others =>
            Result.Kind := Empty_Preview;
            Result.Trusted := Integrity /= Archive.Archives.Entries.Failed;
            return Result;
      end case;
   end Generate_Entry_Metadata;

   function Generate_Entry_From_Accumulator
     (Item        : Archive.Archives.Entries.Archive_Entry;
      Accumulator : Preview_Accumulator;
      Status      : Archive.Archives.Errors.Error_Code := Archive.Archives.Errors.Ok;
      Integrity   : Archive.Archives.Entries.Integrity_State :=
        Archive.Archives.Entries.Verified)
      return Preview_Result
   is
      Result : Preview_Result;
   begin
      case Item.Kind is
         when Archive.Archives.Entries.Directory
            | Archive.Archives.Entries.Symbolic_Link
            | Archive.Archives.Entries.Hard_Link
            | Archive.Archives.Entries.Metadata_Record =>
            return Generate_Entry_Metadata
              (Item, Status, Integrity);
         when others =>
            if Status /= Archive.Archives.Errors.Ok
              or else Integrity = Archive.Archives.Entries.Failed
            then
               return Generate_Entry_Metadata
                 (Item, Status, Integrity);
            end if;

            Result := Finish (Accumulator);
            Result.Trusted := Integrity /= Archive.Archives.Entries.Failed;
            return Result;
      end case;
   end Generate_Entry_From_Accumulator;
end Archive.Preview;
