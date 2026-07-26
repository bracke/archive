package Archive.Archives.Formats is
   type Format_Id is
     (Unknown_Format,
      Tar_Format,
      Tar_GZip_Format,
      Zip_Format,
      GZip_Format,
      Seven_Zip_Format,
      Rar_Format,
      Xz_Format,
      BZip2_Format,
      Zstd_Format,
      Cab_Format,
      Cpio_Format,
      Iso_Format,
      Ar_Format,
      Split_Zip_Format);

   type Detection_Status is
     (Detected,
      Detected_With_Warnings,
      Ambiguous,
      Recognized_Unsupported,
      Invalid,
      Read_Failed);

   type Detection_Result is record
      Status : Detection_Status := Invalid;
      Format : Format_Id := Unknown_Format;
   end record;

   type Format_Capabilities is record
      Can_Index                  : Boolean := False;
      Can_Open_Entry_Streams     : Boolean := False;
      Can_Verify_Metadata        : Boolean := False;
      Can_Verify_Payload         : Boolean := False;
      Supports_Duplicates        : Boolean := False;
      Supports_Symbolic_Links    : Boolean := False;
      Supports_Hard_Links        : Boolean := False;
      Supports_Encryption        : Boolean := False;
      Supports_Random_Access     : Boolean := False;
      Requires_Temporary_Backing : Boolean := False;
      Can_Create                 : Boolean := False;
      Can_Add_Entries            : Boolean := False;
      Can_Replace_Entries        : Boolean := False;
      Can_Remove_Entries         : Boolean := False;
      Can_Rename_Entries         : Boolean := False;
      Requires_Rewrite_For_Update : Boolean := False;
   end record;

   function Stable_Id (Format : Format_Id) return String;
   function Name_Key (Format : Format_Id) return String;
   function Description_Key (Format : Format_Id) return String;
   function Extension_Hints (Format : Format_Id) return String;
   function Capabilities (Format : Format_Id) return Format_Capabilities;
   function Detect_File
     (Path            : String;
      Max_Probe_Bytes : Positive := 32_774)
      return Detection_Result;
end Archive.Archives.Formats;
