with Archive.Archives.Errors;
with Archive.Archives.Streams;
with Zlib;

package body Archive.Archives.Formats is
   use type Archive.Archives.Errors.Error_Code;
   use type Zlib.Byte;

   function Stable_Id (Format : Format_Id) return String is
   begin
      case Format is
         when Unknown_Format => return "unknown";
         when Tar_Format => return "tar";
         when Tar_GZip_Format => return "tar.gz";
         when Zip_Format => return "zip";
         when GZip_Format => return "gzip";
         when Seven_Zip_Format => return "7z";
         when Rar_Format => return "rar";
         when Xz_Format => return "xz";
         when BZip2_Format => return "bzip2";
         when Zstd_Format => return "zstd";
         when Cab_Format => return "cab";
         when Cpio_Format => return "cpio";
         when Iso_Format => return "iso";
         when Ar_Format => return "ar";
         when Split_Zip_Format => return "split_zip";
      end case;
   end Stable_Id;

   function Name_Key (Format : Format_Id) return String is
   begin
      return "format." & Stable_Id (Format) & ".name";
   end Name_Key;

   function Description_Key (Format : Format_Id) return String is
   begin
      return "format." & Stable_Id (Format) & ".description";
   end Description_Key;

   function Extension_Hints (Format : Format_Id) return String is
   begin
      case Format is
         when Tar_Format => return ".tar";
         when Tar_GZip_Format => return ".tar.gz;.tgz";
         when Zip_Format => return ".zip";
         when GZip_Format => return ".gz";
         when Seven_Zip_Format => return ".7z";
         when Rar_Format => return ".rar";
         when Xz_Format => return ".xz";
         when BZip2_Format => return ".bz2;.bzip2";
         when Zstd_Format => return ".zst;.zstd";
         when Cab_Format => return ".cab";
         when Cpio_Format => return ".cpio";
         when Iso_Format => return ".iso";
         when Ar_Format => return ".a;.ar";
         when Split_Zip_Format => return ".z01;.zip";
         when Unknown_Format => return "";
      end case;
   end Extension_Hints;

   function Capabilities (Format : Format_Id) return Format_Capabilities is
   begin
      case Format is
         when Tar_Format =>
            return
              (Can_Index                   => True,
               Can_Open_Entry_Streams      => True,
               Can_Verify_Metadata         => True,
               Can_Verify_Payload          => True,
               Supports_Duplicates         => True,
               Supports_Symbolic_Links     => True,
               Supports_Hard_Links         => True,
               Supports_Encryption         => False,
               Supports_Random_Access      => False,
               Requires_Temporary_Backing  => False,
               Can_Create                  => True,
               Can_Add_Entries             => True,
               Can_Replace_Entries         => True,
               Can_Remove_Entries          => True,
               Can_Rename_Entries          => True,
               Requires_Rewrite_For_Update => True);
         when Tar_GZip_Format =>
            return
              (Can_Index                   => True,
               Can_Open_Entry_Streams      => True,
               Can_Verify_Metadata         => True,
               Can_Verify_Payload          => True,
               Supports_Duplicates         => True,
               Supports_Symbolic_Links     => True,
               Supports_Hard_Links         => True,
               Supports_Encryption         => False,
               Supports_Random_Access      => False,
               Requires_Temporary_Backing  => True,
               Can_Create                  => True,
               Can_Add_Entries             => True,
               Can_Replace_Entries         => True,
               Can_Remove_Entries          => True,
               Can_Rename_Entries          => True,
               Requires_Rewrite_For_Update => True);
         when Zip_Format =>
            return
              (Can_Index                   => True,
               Can_Open_Entry_Streams      => True,
               Can_Verify_Metadata         => True,
               Can_Verify_Payload          => True,
               Supports_Duplicates         => True,
               Supports_Symbolic_Links     => False,
               Supports_Hard_Links         => False,
               Supports_Encryption         => True,
               Supports_Random_Access      => True,
               Requires_Temporary_Backing  => False,
               Can_Create                  => True,
               Can_Add_Entries             => True,
               Can_Replace_Entries         => True,
               Can_Remove_Entries          => True,
               Can_Rename_Entries          => True,
               Requires_Rewrite_For_Update => True);
         when GZip_Format =>
            return
              (Can_Index                   => True,
               Can_Open_Entry_Streams      => True,
               Can_Verify_Metadata         => False,
               Can_Verify_Payload          => True,
               Supports_Duplicates         => False,
               Supports_Symbolic_Links     => False,
               Supports_Hard_Links         => False,
               Supports_Encryption         => False,
               Supports_Random_Access      => False,
               Requires_Temporary_Backing  => False,
               Can_Create                  => True,
               Can_Add_Entries             => False,
               Can_Replace_Entries         => False,
               Can_Remove_Entries          => False,
               Can_Rename_Entries          => True,
               Requires_Rewrite_For_Update => True);
         when others =>
            return (others => False);
      end case;
   end Capabilities;

   function B (Bytes : Zlib.Byte_Array; Offset : Natural) return Zlib.Byte is
   begin
      return Bytes (Bytes'First + Offset);
   end B;

   function Detect_Buffer (Bytes : Zlib.Byte_Array) return Detection_Result is
   begin
      if Bytes'Length >= 6
        and then B (Bytes, 0) = 16#37#
        and then B (Bytes, 1) = 16#7A#
        and then B (Bytes, 2) = 16#BC#
        and then B (Bytes, 3) = 16#AF#
        and then B (Bytes, 4) = 16#27#
        and then B (Bytes, 5) = 16#1C#
      then
         return (Recognized_Unsupported, Seven_Zip_Format);
      elsif Bytes'Length >= 7
        and then B (Bytes, 0) = 16#52#
        and then B (Bytes, 1) = 16#61#
        and then B (Bytes, 2) = 16#72#
        and then B (Bytes, 3) = 16#21#
        and then B (Bytes, 4) = 16#1A#
        and then B (Bytes, 5) = 16#07#
      then
         return (Recognized_Unsupported, Rar_Format);
      elsif Bytes'Length >= 6
        and then B (Bytes, 0) = 16#FD#
        and then B (Bytes, 1) = 16#37#
        and then B (Bytes, 2) = 16#7A#
        and then B (Bytes, 3) = 16#58#
        and then B (Bytes, 4) = 16#5A#
        and then B (Bytes, 5) = 16#00#
      then
         return (Recognized_Unsupported, Xz_Format);
      elsif Bytes'Length >= 4
        and then B (Bytes, 0) = 16#28#
        and then B (Bytes, 1) = 16#B5#
        and then B (Bytes, 2) = 16#2F#
        and then B (Bytes, 3) = 16#FD#
      then
         return (Recognized_Unsupported, Zstd_Format);
      elsif Bytes'Length >= 3
        and then B (Bytes, 0) = 16#42#
        and then B (Bytes, 1) = 16#5A#
        and then B (Bytes, 2) = 16#68#
      then
         return (Recognized_Unsupported, BZip2_Format);
      elsif Bytes'Length >= 4
        and then B (Bytes, 0) = Character'Pos ('M')
        and then B (Bytes, 1) = Character'Pos ('S')
        and then B (Bytes, 2) = Character'Pos ('C')
        and then B (Bytes, 3) = Character'Pos ('F')
      then
         return (Recognized_Unsupported, Cab_Format);
      elsif Bytes'Length >= 6
        and then B (Bytes, 0) = Character'Pos ('0')
        and then B (Bytes, 1) = Character'Pos ('7')
        and then B (Bytes, 2) = Character'Pos ('0')
        and then B (Bytes, 3) = Character'Pos ('7')
        and then B (Bytes, 4) = Character'Pos ('0')
        and then (B (Bytes, 5) = Character'Pos ('1')
                  or else B (Bytes, 5) = Character'Pos ('2'))
      then
         return (Recognized_Unsupported, Cpio_Format);
      elsif Bytes'Length >= 8
        and then B (Bytes, 0) = Character'Pos ('!')
        and then B (Bytes, 1) = Character'Pos ('<')
        and then B (Bytes, 2) = Character'Pos ('a')
        and then B (Bytes, 3) = Character'Pos ('r')
        and then B (Bytes, 4) = Character'Pos ('c')
        and then B (Bytes, 5) = Character'Pos ('h')
        and then B (Bytes, 6) = Character'Pos ('>')
        and then B (Bytes, 7) = 16#0A#
      then
         return (Recognized_Unsupported, Ar_Format);
      elsif Bytes'Length >= 4
        and then B (Bytes, 0) = 16#50#
        and then B (Bytes, 1) = 16#4B#
        and then B (Bytes, 2) = 16#07#
        and then B (Bytes, 3) = 16#08#
      then
         return (Recognized_Unsupported, Split_Zip_Format);
      elsif Bytes'Length >= 4
        and then B (Bytes, 0) = 16#50#
        and then B (Bytes, 1) = 16#4B#
        and then (B (Bytes, 2) = 16#03# or else B (Bytes, 2) = 16#05# or else B (Bytes, 2) = 16#07#)
        and then (B (Bytes, 3) = 16#04# or else B (Bytes, 3) = 16#06# or else B (Bytes, 3) = 16#08#)
      then
         return (Detected, Zip_Format);
      elsif Zlib.Looks_Like_GZip_Header (Bytes) then
         return (Detected, GZip_Format);
      elsif Bytes'Length >= 265
        and then B (Bytes, 257) = Character'Pos ('u')
        and then B (Bytes, 258) = Character'Pos ('s')
        and then B (Bytes, 259) = Character'Pos ('t')
        and then B (Bytes, 260) = Character'Pos ('a')
        and then B (Bytes, 261) = Character'Pos ('r')
      then
         return (Detected, Tar_Format);
      elsif Bytes'Length >= 32_774
        and then B (Bytes, 32_769) = Character'Pos ('C')
        and then B (Bytes, 32_770) = Character'Pos ('D')
        and then B (Bytes, 32_771) = Character'Pos ('0')
        and then B (Bytes, 32_772) = Character'Pos ('0')
        and then B (Bytes, 32_773) = Character'Pos ('1')
      then
         return (Recognized_Unsupported, Iso_Format);
      else
         return (Invalid, Unknown_Format);
      end if;
   end Detect_Buffer;

   function Detect_File
     (Path            : String;
      Max_Probe_Bytes : Positive := 32_774)
      return Detection_Result
   is
      Probe : constant Archive.Archives.Streams.Buffered_Source :=
        Archive.Archives.Streams.Read_Prefix (Path, Max_Probe_Bytes);
   begin
      if Probe.Status /= Archive.Archives.Errors.Ok then
         return (Status => Read_Failed, Format => Unknown_Format);
      end if;

      return Detect_Buffer (Probe.Bytes);
   end Detect_File;
end Archive.Archives.Formats;
