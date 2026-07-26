package body Archive.Archives.Capabilities is
   use type Archive.Archives.Entries.Compression_Method;
   use type Archive.Archives.Entries.Encryption_State;
   use type Archive.Archives.Entries.Entry_Kind;
   use type Archive.Archives.Entries.Path_Safety;

   function Unavailable_Key (Reason : Entry_Unavailable_Reason) return String is
   begin
      case Reason is
         when Available => return "";
         when No_Entry_Selected => return "command.unavailable.no_selection";
         when Encrypted_Entry => return "unavailable.encrypted";
         when Unsupported_Method => return "unavailable.unsupported_method";
         when Unsafe_Path => return "unavailable.unsafe_path";
         when Unsupported_Entry_Kind => return "unavailable.unsupported_entry_kind";
         when Unsupported_Write_Action => return "command.unavailable.read_only_archive";
      end case;
   end Unavailable_Key;

   function For_Entry
     (Item             : Archive.Archives.Entries.Archive_Entry;
      Archive_Writable : Boolean := True)
      return Entry_Capabilities
   is
      Regular : constant Boolean := Item.Kind = Archive.Archives.Entries.Regular_File;
      Directory : constant Boolean := Item.Kind = Archive.Archives.Entries.Directory;
      Link    : constant Boolean :=
        Item.Kind in Archive.Archives.Entries.Symbolic_Link | Archive.Archives.Entries.Hard_Link;
      Supported_Kind : constant Boolean :=
        Item.Kind in Archive.Archives.Entries.Regular_File | Archive.Archives.Entries.Directory;
      Supported_Method : constant Boolean :=
        Item.Method in Archive.Archives.Entries.Zip_Stored | Archive.Archives.Entries.Zip_Deflate
          | Archive.Archives.Entries.GZip_Deflate | Archive.Archives.Entries.Zstd_Compression
          | Archive.Archives.Entries.No_Compression;
      Safe : constant Boolean := Item.Safety = Archive.Archives.Entries.Safe_Path;
      Read_Available : constant Boolean :=
        Supported_Kind
        and then Supported_Method
        and then Safe
        and then Item.Encryption /= Archive.Archives.Entries.Encrypted;
      Reason : constant Entry_Unavailable_Reason :=
        (if Item.Encryption = Archive.Archives.Entries.Encrypted then Encrypted_Entry
         elsif not Supported_Method then Unsupported_Method
         elsif not Safe then Unsafe_Path
         elsif not Supported_Kind then Unsupported_Entry_Kind
         else Available);
      Write_Reason : constant Entry_Unavailable_Reason :=
        (if not Archive_Writable then Unsupported_Write_Action
         elsif not Safe then Unsafe_Path
         else Available);
      Replace_Reason : constant Entry_Unavailable_Reason :=
        (if Write_Reason /= Available then Write_Reason
         elsif not Regular then Unsupported_Entry_Kind
         else Available);
      Extract_Available : constant Boolean := Read_Available and then (Regular or else Directory);
      Verify_Available : constant Boolean := Supported_Method and then Regular;
      Follow_Available : constant Boolean := Link and then Safe;
   begin
      return
        (Can_Preview         => Read_Available and then (Regular or else Directory or else Link),
         Can_Extract         => Extract_Available,
         Can_Verify          => Verify_Available,
         Can_Open_Externally => Read_Available and then Regular,
         Can_Follow_Link     => Follow_Available,
         Can_Add             => Archive_Writable,
         Can_Replace         => Replace_Reason = Available,
         Can_Remove          => Write_Reason = Available,
         Can_Rename          => Write_Reason = Available,
         Reason              => (if Reason = Available and then not Archive_Writable
                                 then Unsupported_Write_Action
                                 else Reason),
         Preview_Reason      => (if Read_Available and then (Regular or else Directory or else Link)
                                 then Available else Reason),
         Extract_Reason      => (if Extract_Available then Available else Reason),
         Verify_Reason       => (if Verify_Available then Available else Reason),
         Open_External_Reason => (if Read_Available and then Regular then Available else Reason),
         Follow_Link_Reason  => (if Follow_Available then Available
                                 elsif not Safe then Unsafe_Path
                                 else Unsupported_Entry_Kind),
         Add_Reason          => (if Archive_Writable then Available else Unsupported_Write_Action),
         Replace_Reason      => Replace_Reason,
         Remove_Reason       => Write_Reason,
         Rename_Reason       => Write_Reason);
   end For_Entry;
end Archive.Archives.Capabilities;
