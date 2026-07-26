with Ada.Command_Line;
with Ada.Directories;
with Ada.Streams;
with Ada.Streams.Stream_IO;
with Ada.Strings.Unbounded;
with Ada.Text_IO;
with Interfaces;

with Archive.Types;
with Archive.Verification.CRC32;
with Project_Tools.Text;
with Zlib;

procedure Release_Report is
   use Ada.Text_IO;
   use Ada.Strings.Unbounded;
   use Project_Tools.Text;
   use type Interfaces.Unsigned_32;
   use type Ada.Streams.Stream_Element_Offset;
   use type Ada.Directories.File_Kind;

   function Tests_Root return String is
      Here : constant String := Ada.Directories.Current_Directory;
   begin
      if Ada.Directories.Exists (Here & "/archive_tests.gpr") then
         return Here;
      elsif Ada.Directories.Exists (Here & "/../archive_tests.gpr") then
         return Ada.Directories.Full_Name (Here & "/..");
      elsif Ada.Directories.Exists (Here & "/tests/archive_tests.gpr") then
         return Ada.Directories.Full_Name (Here & "/tests");
      else
         return Here;
      end if;
   end Tests_Root;

   Tests : constant String := Tests_Root;
   Root  : constant String := Ada.Directories.Full_Name (Tests & "/..");

   Missing : Natural := 0;
   Invalid : Natural := 0;
   Package_Input_Count          : Natural := 0;
   Required_Package_Input_Count : Natural := 0;
   Package_Byte_Count           : Natural := 0;
   Package_CRC_Xor              : Interfaces.Unsigned_32 := 0;

   type Release_Gate_Id is
     (Validate_Repository_State,
      Validate_Manifests_And_Resolution,
      Build_Full_Graph_Release,
      Run_AUnit_Suite,
      Run_Integration_Tests,
      Run_Extraction_Security_Tests,
      Run_Malformed_Input_Corpus,
      Run_Deterministic_Mutation_Tests,
      Run_Localization_Coverage,
      Run_Fixture_Validation,
      Run_Architecture_Checks,
      Run_Documentation_Checks,
      Run_Dependency_License_Checks,
      Run_GNATprove,
      Prepare_Package,
      Inspect_Package,
      Run_Packaged_Smoke_Test,
      Generate_Artifact_Checksums,
      Generate_Release_Report,
      Verify_Cleanliness);

   subtype Enforced_Gate_Id is Release_Gate_Id
     with Static_Predicate => Enforced_Gate_Id in
       Validate_Repository_State
       | Validate_Manifests_And_Resolution
       | Build_Full_Graph_Release
       | Run_AUnit_Suite
       | Run_Integration_Tests
       | Run_Extraction_Security_Tests
       | Run_Malformed_Input_Corpus
       | Run_Deterministic_Mutation_Tests
       | Run_Localization_Coverage
       | Run_Fixture_Validation
       | Run_Architecture_Checks
       | Run_Documentation_Checks
       | Run_Dependency_License_Checks
       | Run_GNATprove
       | Prepare_Package
       | Inspect_Package
       | Run_Packaged_Smoke_Test
       | Generate_Artifact_Checksums
       | Generate_Release_Report
       | Verify_Cleanliness;

   function Gate_Key (Gate : Release_Gate_Id) return String is
   begin
      case Gate is
         when Validate_Repository_State => return "validate_repository_state";
         when Validate_Manifests_And_Resolution => return "validate_manifests_and_resolution";
         when Build_Full_Graph_Release => return "build_full_graph_release";
         when Run_AUnit_Suite => return "run_aunit_suite";
         when Run_Integration_Tests => return "run_integration_tests";
         when Run_Extraction_Security_Tests => return "run_extraction_security_tests";
         when Run_Malformed_Input_Corpus => return "run_malformed_input_corpus";
         when Run_Deterministic_Mutation_Tests => return "run_deterministic_mutation_tests";
         when Run_Localization_Coverage => return "run_localization_coverage";
         when Run_Fixture_Validation => return "run_fixture_validation";
         when Run_Architecture_Checks => return "run_architecture_checks";
         when Run_Documentation_Checks => return "run_documentation_checks";
         when Run_Dependency_License_Checks => return "run_dependency_license_checks";
         when Run_GNATprove => return "run_gnatprove";
         when Prepare_Package => return "prepare_package";
         when Inspect_Package => return "inspect_package";
         when Run_Packaged_Smoke_Test => return "run_packaged_smoke_test";
         when Generate_Artifact_Checksums => return "generate_artifact_checksums";
         when Generate_Release_Report => return "generate_release_report";
         when Verify_Cleanliness => return "verify_cleanliness";
      end case;
   end Gate_Key;

   function Gate_Status (Gate : Release_Gate_Id) return String is
   begin
      if Gate in Enforced_Gate_Id then
         return "enforced";
      else
         return "tracked";
      end if;
   end Gate_Status;

   function Total_Release_Gates return Natural is
   begin
      return Release_Gate_Id'Pos (Release_Gate_Id'Last)
        - Release_Gate_Id'Pos (Release_Gate_Id'First) + 1;
   end Total_Release_Gates;

   function Enforced_Release_Gates return Natural is
      Count : Natural := 0;
   begin
      for Gate in Release_Gate_Id loop
         if Gate in Enforced_Gate_Id then
            Count := Count + 1;
         end if;
      end loop;
      return Count;
   end Enforced_Release_Gates;

   function To_Hex8 (Value : Interfaces.Unsigned_32) return String is
      Hex_Digit : constant String := "0123456789ABCDEF";
      V         : Interfaces.Unsigned_32 := Value;
      Result    : String (1 .. 8);
   begin
      for Index in reverse Result'Range loop
         Result (Index) := Hex_Digit (Integer (V mod 16) + 1);
         V := V / 16;
      end loop;
      return Result;
   end To_Hex8;

   type File_CRC_Result is record
      Bytes : Natural := 0;
      CRC   : Archive.Types.CRC32_Value := 0;
   end record;

   function Compute_File_CRC32 (Path : String) return File_CRC_Result is
      Chunk_Size : constant Ada.Streams.Stream_Element_Count := 8_192;
      File       : Ada.Streams.Stream_IO.File_Type;
      State      : Archive.Verification.CRC32.CRC32_State :=
        Archive.Verification.CRC32.Initial;
      Total      : Natural := 0;
   begin
      Ada.Streams.Stream_IO.Open (File, Ada.Streams.Stream_IO.In_File, Path);
      while not Ada.Streams.Stream_IO.End_Of_File (File) loop
         declare
            Raw  : Ada.Streams.Stream_Element_Array (1 .. Chunk_Size);
            Last : Ada.Streams.Stream_Element_Offset;
         begin
            Ada.Streams.Stream_IO.Read (File, Raw, Last);
            if Last >= Raw'First then
               declare
                  Count : constant Natural :=
                    Natural (Last - Raw'First + 1);
                  Chunk : Zlib.Byte_Array (1 .. Count);
               begin
                  for Index in Chunk'Range loop
                     Chunk (Index) :=
                       Zlib.Byte
                         (Raw
                            (Raw'First
                             + Ada.Streams.Stream_Element_Offset (Index - 1)));
                  end loop;

                  Archive.Verification.CRC32.Update (State, Chunk);
                  Total := Total + Count;
               end;
            end if;
         end;
      end loop;
      Ada.Streams.Stream_IO.Close (File);

      return
        (Bytes => Total,
         CRC   => Archive.Verification.CRC32.Final (State));
   exception
      when others =>
         if Ada.Streams.Stream_IO.Is_Open (File) then
            Ada.Streams.Stream_IO.Close (File);
         end if;
         raise;
   end Compute_File_CRC32;

   procedure Require_File (Path : String) is
   begin
      if not Ada.Directories.Exists (Path) then
         Missing := Missing + 1;
         Put_Line (Standard_Error, Path & ": missing release-report input");
      end if;
   end Require_File;

   procedure Require_Text
     (Relative_Path : String;
      Marker        : String)
   is
      Path : constant String := Root & "/" & Relative_Path;
   begin
      if not Ada.Directories.Exists (Path) then
         Missing := Missing + 1;
         Put_Line (Standard_Error, Path & ": missing release-report input");
         return;
      end if;

      declare
         Content : constant String := To_String (Read_Text_File (Path));
      begin
         if not Contains (Content, Marker) then
            Invalid := Invalid + 1;
            Put_Line
              (Standard_Error,
               Path & ": missing release-report marker: " & Marker);
         end if;
      end;
   end Require_Text;

   procedure Require_Tests_Text
     (Relative_Path : String;
      Marker        : String)
   is
      Path : constant String := Tests & "/" & Relative_Path;
   begin
      if not Ada.Directories.Exists (Path) then
         Missing := Missing + 1;
         Put_Line (Standard_Error, Path & ": missing release-report input");
         return;
      end if;

      declare
         Content : constant String := To_String (Read_Text_File (Path));
      begin
         if not Contains (Content, Marker) then
            Invalid := Invalid + 1;
            Put_Line
              (Standard_Error,
               Path & ": missing release-report marker: " & Marker);
         end if;
      end;
   end Require_Tests_Text;

   function Ready return Boolean is
   begin
      return Missing = 0 and then Invalid = 0;
   end Ready;

   function JSON_Report return String is
      Gates : Unbounded_String;
   begin
      for Gate in Release_Gate_Id loop
         if Length (Gates) > 0 then
            Append (Gates, "," & ASCII.LF);
         end if;
         Append
           (Gates,
            "    {""id"": """ & Gate_Key (Gate) & """, ""required"": true, ""status"": """
            & Gate_Status (Gate) & """}");
      end loop;

      return "{"
        & ASCII.LF & "  ""tool"": ""archive release_report"","
        & ASCII.LF & "  ""schema"": 1,"
        & ASCII.LF & "  ""root"": """ & Root & ""","
        & ASCII.LF & "  ""tests_root"": """ & Tests & ""","
        & ASCII.LF & "  ""required_inputs_missing"": " & Missing'Image & ","
        & ASCII.LF & "  ""required_inputs_invalid"": " & Invalid'Image & ","
        & ASCII.LF & "  ""package_input_count"": " & Package_Input_Count'Image & ","
        & ASCII.LF & "  ""required_package_input_count"": " & Required_Package_Input_Count'Image & ","
        & ASCII.LF & "  ""package_byte_count"": " & Package_Byte_Count'Image & ","
        & ASCII.LF & "  ""package_crc32_xor"": """ & To_Hex8 (Package_CRC_Xor) & ""","
        & ASCII.LF & "  ""mandatory_release_gates"": " & Total_Release_Gates'Image & ","
        & ASCII.LF & "  ""enforced_release_gates"": " & Enforced_Release_Gates'Image & ","
        & ASCII.LF & "  ""checks"": ["
        & ASCII.LF & "    ""repository inputs"","
        & ASCII.LF & "    ""full graph release builds"","
        & ASCII.LF & "    ""ci delegation"","
        & ASCII.LF & "    ""fixture manifest"","
        & ASCII.LF & "    ""integration tests"","
        & ASCII.LF & "    ""malformed/security corpus"","
        & ASCII.LF & "    ""extraction security tests"","
        & ASCII.LF & "    ""deterministic mutation tests"","
        & ASCII.LF & "    ""dependency/license manifests"","
        & ASCII.LF & "    ""GNATprove"","
        & ASCII.LF & "    ""package manifest"","
        & ASCII.LF & "    ""packaged smoke test"","
        & ASCII.LF & "    ""release cleanliness"","
        & ASCII.LF & "    ""documentation markers"","
        & ASCII.LF & "    ""catalog markers"""
        & ASCII.LF & "  ],"
        & ASCII.LF & "  ""release_gates"": ["
        & ASCII.LF & To_String (Gates)
        & ASCII.LF & "  ],"
        & ASCII.LF & "  ""status"": """ & (if Ready then "ready" else "failed") & """"
        & ASCII.LF & "}";
   end JSON_Report;

   procedure Write_Report (Path : String; Text : String) is
      File : Ada.Text_IO.File_Type;
   begin
      Ada.Text_IO.Create (File, Ada.Text_IO.Out_File, Path);
      Ada.Text_IO.Put_Line (File, Text);
      Ada.Text_IO.Close (File);
   exception
      when others =>
         if Ada.Text_IO.Is_Open (File) then
            Ada.Text_IO.Close (File);
         end if;
         raise;
   end Write_Report;

   function Field_Value (Line : String; Name : String) return String is
      Prefix : constant String := Name & "=";
      Start  : Positive := Line'First;
   begin
      while Start <= Line'Last loop
         while Start <= Line'Last and then Line (Start) = ' ' loop
            Start := Start + 1;
         end loop;

         exit when Start > Line'Last;

         declare
            Finish : Natural := Start;
         begin
            while Finish <= Line'Last and then Line (Finish) /= ' ' loop
               Finish := Finish + 1;
            end loop;

            if Finish > Start
              and then Finish - Start >= Prefix'Length
              and then Line (Start .. Start + Prefix'Length - 1) = Prefix
            then
               return Line (Start + Prefix'Length .. Finish - 1);
            end if;

            Start := Finish + 1;
         end;
      end loop;

      return "";
   end Field_Value;

   procedure Check_Package_Manifest is
      Manifest : constant String := Root & "/packaging/manifest.txt";
      File     : Ada.Text_IO.File_Type;
      Buffer   : String (1 .. 1024);
      Last     : Natural;
      Line_No  : Natural := 0;
      Count    : Natural := 0;

      function Known_Package_Kind (Value : String) return Boolean is
      begin
         return Value in "documentation" | "license" | "catalog" | "test-corpus";
      end Known_Package_Kind;

      function Safe_Package_Path (Value : String) return Boolean is
      begin
         if Value = ""
           or else Starts_With (Value, "/")
           or else Starts_With (Value, "\")
           or else Starts_With (Value, "../")
           or else Starts_With (Value, "generated:")
         then
            return False;
         end if;

         for Index in Value'Range loop
            if Value (Index) = ':' then
               return False;
            elsif Value (Index) = '.'
              and then Index < Value'Last
              and then Value (Index + 1) = '.'
              and then (Index = Value'First or else Value (Index - 1) = '/')
              and then (Index + 1 = Value'Last or else Value (Index + 2) = '/')
            then
               return False;
            end if;
         end loop;

         return True;
      end Safe_Package_Path;
   begin
      if not Ada.Directories.Exists (Manifest) then
         Missing := Missing + 1;
         Put_Line (Standard_Error, Manifest & ": missing package manifest");
         return;
      end if;

      Ada.Text_IO.Open (File, Ada.Text_IO.In_File, Manifest);
      while not Ada.Text_IO.End_Of_File (File) loop
         Ada.Text_IO.Get_Line (File, Buffer, Last);
         Line_No := Line_No + 1;

         declare
            Line     : constant String := Buffer (1 .. Last);
            Path     : constant String := Field_Value (Line, "path");
            Kind     : constant String := Field_Value (Line, "kind");
            Required : constant String := Field_Value (Line, "required");
         begin
            if Last = 0 or else Line (Line'First) = '#' then
               null;
            elsif Starts_With (Line, "package-file ") then
               Count := Count + 1;
               Package_Input_Count := Package_Input_Count + 1;
               if Path = "" or else Kind = "" or else Required = "" then
                  Invalid := Invalid + 1;
                  Put_Line
                    (Standard_Error,
                     Manifest & ":" & Line_No'Image & ": package-file has missing fields");
               elsif not Safe_Package_Path (Path) then
                  Invalid := Invalid + 1;
                  Put_Line
                    (Standard_Error,
                     Manifest & ":" & Line_No'Image & ": package-file path is unsafe");
               elsif not Known_Package_Kind (Kind) then
                  Invalid := Invalid + 1;
                  Put_Line
                    (Standard_Error,
                     Manifest & ":" & Line_No'Image & ": unknown package-file kind " & Kind);
               elsif Required /= "true" and then Required /= "false" then
                  Invalid := Invalid + 1;
                  Put_Line
                    (Standard_Error,
                     Manifest & ":" & Line_No'Image & ": required must be true or false");
               else
                  if Required = "true" then
                     Required_Package_Input_Count := Required_Package_Input_Count + 1;
                  end if;

                  if not Ada.Directories.Exists (Root & "/" & Path) then
                     if Required = "true" then
                        Missing := Missing + 1;
                        Put_Line
                          (Standard_Error,
                           Root & "/" & Path & ": required package input is missing");
                     end if;
                  else
                     if Ada.Directories.Kind (Root & "/" & Path) /= Ada.Directories.Ordinary_File then
                        Invalid := Invalid + 1;
                        Put_Line
                          (Standard_Error,
                           Root & "/" & Path & ": package input is not an ordinary file");
                     end if;

                     declare
                        Hashed : constant File_CRC_Result :=
                          Compute_File_CRC32 (Root & "/" & Path);
                     begin
                        Package_Byte_Count := Package_Byte_Count + Hashed.Bytes;
                        Package_CRC_Xor :=
                          Package_CRC_Xor xor Interfaces.Unsigned_32 (Hashed.CRC);
                     end;
                  end if;
               end if;
            else
               Invalid := Invalid + 1;
               Put_Line
                 (Standard_Error,
                  Manifest & ":" & Line_No'Image & ": unknown package manifest record");
            end if;
         end;
      end loop;
      Ada.Text_IO.Close (File);

      if Count = 0 then
         Invalid := Invalid + 1;
         Put_Line (Standard_Error, Manifest & ": package manifest contains no package-file records");
      end if;
   exception
      when others =>
         if Ada.Text_IO.Is_Open (File) then
            Ada.Text_IO.Close (File);
         end if;
         raise;
   end Check_Package_Manifest;

   procedure Check_Fixture_Manifest is
      Manifest : constant String := Root & "/tests/fixtures/manifest.txt";
      File     : Ada.Text_IO.File_Type;
      Buffer   : String (1 .. 1024);
      Last     : Natural;
      Line_No  : Natural := 0;
      Count    : Natural := 0;
      Has_Plain : Boolean := False;
      Has_Tar : Boolean := False;
      Has_Settings_Current : Boolean := False;
      Has_Settings_Migration : Boolean := False;
      Has_Settings_Invalid : Boolean := False;
      Has_Tar_Gzip : Boolean := False;
      Has_Tar_Duplicate : Boolean := False;
      Has_Ar : Boolean := False;
      Has_Cpio : Boolean := False;
      Has_Iso : Boolean := False;
      Has_Cab_Unsupported : Boolean := False;
      Has_Xz_Unsupported : Boolean := False;
      Has_Xz : Boolean := False;
      Has_Seven_Zip_Encrypted : Boolean := False;
      Has_Rar_Unsupported : Boolean := False;
      Has_Split_Zip_Unsupported : Boolean := False;
      Has_BZip2 : Boolean := False;
      Has_Zstd : Boolean := False;
      Has_Zip_Stored : Boolean := False;
      Has_Zip_Deflate : Boolean := False;
      Has_Zip_Descriptor : Boolean := False;
      Has_Zip64 : Boolean := False;
      Has_Zip_Unsupported : Boolean := False;
      Has_Zip_PPMd : Boolean := False;
      Has_Zip_Encrypted : Boolean := False;
      Has_Zip_Multi_Disk : Boolean := False;
      Has_Gzip : Boolean := False;
      Has_Gzip_Empty : Boolean := False;
      Has_Zip_Bad_CRC : Boolean := False;
      Has_Zip_Central_CRC_Mismatch : Boolean := False;
      Has_Zip_Unicode_Bad_CRC : Boolean := False;
      Has_Zip_Unicode_Bad_Version : Boolean := False;
      Has_Zip64_Missing_Extra : Boolean := False;
      Has_Zip64_Too_Large : Boolean := False;
      Has_Zip_Local_Size_Mismatch : Boolean := False;
      Has_Zip_Bad_Local_Signature : Boolean := False;
      Has_Gzip_Bad_Header_CRC : Boolean := False;
      Has_Gzip_Bad_Trailer : Boolean := False;

      procedure Require_Field
        (Line        : String;
         Field       : String;
         Line_Number : Natural)
      is
      begin
         if Field_Value (Line, Field) = "" then
            Invalid := Invalid + 1;
            Put_Line
              (Standard_Error,
               Manifest & ":" & Line_Number'Image
               & ": fixture record is missing " & Field);
         end if;
      end Require_Field;

      type Generated_Fixture_Metadata is record
         Known : Boolean := False;
         Size  : Natural := 0;
         CRC   : String (1 .. 8) := "00000000";
      end record;

      function Generated_Metadata (Id : String) return Generated_Fixture_Metadata is
      begin
         if Id = "tar-basic" then
            return (True, 2_048, "AE42BDC4");
         elsif Id = "tar-gzip-basic" then
            return (True, 98, "322CAE1E");
         elsif Id = "tar-duplicate-path" then
            return (True, 3_072, "1A4AF7A3");
         elsif Id = "ar-basic" then
            return (True, 72, "9827F2B3");
         elsif Id = "cpio-basic" then
            return (True, 244, "D5B2DBE1");
         elsif Id = "iso-basic" then
            return (True, 49_152, "5AF299FA");
         elsif Id = "cab-unsupported-method" then
            return (True, 77, "67F88E19");
         elsif Id = "xz-unsupported-check" then
            return (True, 56, "C7296238");
         elsif Id = "xz-basic" then
            return (True, 56, "2CB5327A");
         elsif Id = "seven-zip-encrypted" then
            return (True, 163, "5FE648EF");
         elsif Id = "rar-unsupported" then
            return (True, 20, "EAEAB33A");
         elsif Id = "split-zip-unsupported" then
            return (True, 8, "5B7D7655");
         elsif Id = "bzip2-basic" then
            return (True, 38, "ED9E5814");
         elsif Id = "zstd-basic" then
            return (True, 19, "F4A2B9CC");
         elsif Id = "zip-stored-basic" then
            return (True, 111, "91E2A6FC");
         elsif Id = "zip-deflate-basic" then
            return (True, 113, "9ABAE3AF");
         elsif Id = "zip-data-descriptor" then
            return (True, 127, "9B0623BB");
         elsif Id = "zip-zip64-basic" then
            return (True, 151, "8777E7F4");
         elsif Id = "zip-unicode-path" then
            return (True, 131, "4DFF89CE");
         elsif Id = "gzip-basic" then
            return (True, 23, "BB1C56C2");
         elsif Id = "gzip-empty" then
            return (True, 20, "45378550");
         elsif Id = "zip-bad-crc" then
            return (True, 111, "BB182EBC");
         elsif Id = "zip-central-crc-mismatch" then
            return (True, 111, "F05368A1");
         elsif Id = "zip-unicode-path-bad-crc" then
            return (True, 131, "D686D927");
         elsif Id = "zip-unicode-path-bad-version" then
            return (True, 131, "001789A9");
         elsif Id = "zip-unsupported-method" then
            return (True, 111, "D97324F5");
         elsif Id = "zip-ppmd" then
            return (True, 111, "811B9BE2");
         elsif Id = "zip-encrypted" then
            return (True, 111, "CFBFD41F");
         elsif Id = "zip-zip64-missing-extra" then
            return (True, 111, "132876B0");
         elsif Id = "zip-zip64-too-large" then
            return (True, 151, "6D402500");
         elsif Id = "zip-local-size-mismatch" then
            return (True, 111, "FFF9E6F2");
         elsif Id = "zip-bad-local-signature" then
            return (True, 111, "075C7652");
         elsif Id = "zip-truncated-central" then
            return (True, 99, "14DE128C");
         elsif Id = "zip-multi-disk" then
            return (True, 111, "D0D8818C");
         elsif Id = "gzip-bad-header-crc" then
            return (True, 25, "DCD39199");
         elsif Id = "gzip-truncated" then
            return (True, 20, "9F7020DB");
         elsif Id = "gzip-bad-trailer" then
            return (True, 23, "941F1893");
         elsif Id = "tar-truncated" then
            return (True, 648, "057EB66E");
         else
            return (Known => False, Size => 0, CRC => "00000000");
         end if;
      end Generated_Metadata;

      procedure Validate_Fixture_Record (Line : String; Line_Number : Natural) is
         Id        : constant String := Field_Value (Line, "id");
         Path      : constant String := Field_Value (Line, "path");
         Size_Text : constant String := Field_Value (Line, "size");
         CRC_Text  : constant String := Field_Value (Line, "crc32");
         Expected_Size : Natural;
      begin
         if Id = "" or else Path = "" or else Size_Text = "" or else CRC_Text = "" then
            return;
         end if;

         Expected_Size := Natural'Value (Size_Text);

         if Starts_With (Path, "generated:") then
            declare
               Expected : constant Generated_Fixture_Metadata :=
                 Generated_Metadata (Id);
            begin
               if Path /= "generated:" & Id then
                  Invalid := Invalid + 1;
                  Put_Line
                    (Standard_Error,
                     Manifest & ":" & Line_Number'Image
                     & ": generated fixture path must match id");
               elsif not Expected.Known then
                  Invalid := Invalid + 1;
                  Put_Line
                    (Standard_Error,
                     Manifest & ":" & Line_Number'Image
                     & ": unknown generated fixture id " & Id);
               elsif Expected_Size /= Expected.Size then
                  Invalid := Invalid + 1;
                  Put_Line
                    (Standard_Error,
                     Manifest & ":" & Line_Number'Image
                     & ": generated fixture size mismatch for " & Id);
               elsif CRC_Text /= Expected.CRC then
                  Invalid := Invalid + 1;
                  Put_Line
                    (Standard_Error,
                     Manifest & ":" & Line_Number'Image
                     & ": generated fixture CRC mismatch for " & Id);
               end if;
            end;
         else
            if not Starts_With (Path, "tests/fixtures/") then
               Invalid := Invalid + 1;
               Put_Line
                 (Standard_Error,
                  Manifest & ":" & Line_Number'Image
                  & ": checked-in fixture path must stay under tests/fixtures");
            elsif not Ada.Directories.Exists (Root & "/" & Path) then
               Missing := Missing + 1;
               Put_Line
                 (Standard_Error,
                  Root & "/" & Path & ": listed fixture is missing");
            else
               declare
                  Hashed     : constant File_CRC_Result :=
                    Compute_File_CRC32 (Root & "/" & Path);
                  Actual_CRC : constant String :=
                    To_Hex8 (Interfaces.Unsigned_32 (Hashed.CRC));
               begin
                  if Hashed.Bytes /= Expected_Size then
                     Invalid := Invalid + 1;
                     Put_Line
                       (Standard_Error,
                        Root & "/" & Path & ": fixture size mismatch");
                  elsif CRC_Text /= Actual_CRC then
                     Invalid := Invalid + 1;
                     Put_Line
                       (Standard_Error,
                        Root & "/" & Path & ": fixture CRC32 mismatch");
                  end if;
               end;
            end if;
         end if;
      exception
         when Constraint_Error =>
            Invalid := Invalid + 1;
            Put_Line
              (Standard_Error,
               Manifest & ":" & Line_Number'Image
               & ": invalid numeric fixture field");
      end Validate_Fixture_Record;
   begin
      if not Ada.Directories.Exists (Manifest) then
         Missing := Missing + 1;
         Put_Line (Standard_Error, Manifest & ": missing fixture manifest");
         return;
      end if;

      Ada.Text_IO.Open (File, Ada.Text_IO.In_File, Manifest);
      while not Ada.Text_IO.End_Of_File (File) loop
         Ada.Text_IO.Get_Line (File, Buffer, Last);
         Line_No := Line_No + 1;

         declare
            Line : constant String := Buffer (1 .. Last);
            Id   : constant String := Field_Value (Line, "id");
         begin
            if Last = 0 or else Line (Line'First) = '#' then
               null;
            elsif Starts_With (Line, "fixture ") then
               Count := Count + 1;
               Require_Field (Line, "id", Line_No);
               Require_Field (Line, "path", Line_No);
               Require_Field (Line, "format", Line_No);
               Require_Field (Line, "purpose", Line_No);
               Require_Field (Line, "size", Line_No);
               Require_Field (Line, "crc32", Line_No);
               Validate_Fixture_Record (Line, Line_No);

               if Id = "plain-ok" then
                  Has_Plain := True;
               elsif Id = "tar-basic" then
                  Has_Tar := True;
               elsif Id = "settings-current-valid" then
                  Has_Settings_Current := True;
               elsif Id = "settings-schema0-migration" then
                  Has_Settings_Migration := True;
               elsif Id = "settings-invalid-future-schema" then
                  Has_Settings_Invalid := True;
               elsif Id = "tar-gzip-basic" then
                  Has_Tar_Gzip := True;
               elsif Id = "tar-duplicate-path" then
                  Has_Tar_Duplicate := True;
               elsif Id = "ar-basic" then
                  Has_Ar := True;
               elsif Id = "cpio-basic" then
                  Has_Cpio := True;
               elsif Id = "iso-basic" then
                  Has_Iso := True;
               elsif Id = "cab-unsupported-method" then
                  Has_Cab_Unsupported := True;
               elsif Id = "xz-unsupported-check" then
                  Has_Xz_Unsupported := True;
               elsif Id = "xz-basic" then
                  Has_Xz := True;
               elsif Id = "seven-zip-encrypted" then
                  Has_Seven_Zip_Encrypted := True;
               elsif Id = "rar-unsupported" then
                  Has_Rar_Unsupported := True;
               elsif Id = "split-zip-unsupported" then
                  Has_Split_Zip_Unsupported := True;
               elsif Id = "bzip2-basic" then
                  Has_BZip2 := True;
               elsif Id = "zstd-basic" then
                  Has_Zstd := True;
               elsif Id = "zip-stored-basic" then
                  Has_Zip_Stored := True;
               elsif Id = "zip-deflate-basic" then
                  Has_Zip_Deflate := True;
               elsif Id = "zip-data-descriptor" then
                  Has_Zip_Descriptor := True;
               elsif Id = "zip-zip64-basic" then
                  Has_Zip64 := True;
               elsif Id = "zip-unsupported-method" then
                  Has_Zip_Unsupported := True;
               elsif Id = "zip-ppmd" then
                  Has_Zip_PPMd := True;
               elsif Id = "zip-encrypted" then
                  Has_Zip_Encrypted := True;
               elsif Id = "zip-multi-disk" then
                  Has_Zip_Multi_Disk := True;
               elsif Id = "gzip-basic" then
                  Has_Gzip := True;
               elsif Id = "gzip-empty" then
                  Has_Gzip_Empty := True;
               elsif Id = "zip-bad-crc" then
                  Has_Zip_Bad_CRC := True;
               elsif Id = "zip-central-crc-mismatch" then
                  Has_Zip_Central_CRC_Mismatch := True;
               elsif Id = "zip-unicode-path-bad-crc" then
                  Has_Zip_Unicode_Bad_CRC := True;
               elsif Id = "zip-unicode-path-bad-version" then
                  Has_Zip_Unicode_Bad_Version := True;
               elsif Id = "gzip-bad-trailer" then
                  Has_Gzip_Bad_Trailer := True;
               elsif Id = "zip-zip64-missing-extra" then
                  Has_Zip64_Missing_Extra := True;
               elsif Id = "zip-zip64-too-large" then
                  Has_Zip64_Too_Large := True;
               elsif Id = "zip-local-size-mismatch" then
                  Has_Zip_Local_Size_Mismatch := True;
               elsif Id = "zip-bad-local-signature" then
                  Has_Zip_Bad_Local_Signature := True;
               elsif Id = "gzip-bad-header-crc" then
                  Has_Gzip_Bad_Header_CRC := True;
               end if;
            else
               Invalid := Invalid + 1;
               Put_Line
                 (Standard_Error,
                  Manifest & ":" & Line_No'Image & ": unknown fixture manifest record");
            end if;
         end;
      end loop;
      Ada.Text_IO.Close (File);

      if Count = 0 then
         Invalid := Invalid + 1;
         Put_Line (Standard_Error, Manifest & ": fixture manifest contains no fixtures");
      elsif not Has_Plain
        or else not Has_Settings_Current or else not Has_Settings_Migration
        or else not Has_Settings_Invalid
        or else not Has_Tar or else not Has_Tar_Gzip or else not Has_Tar_Duplicate
        or else not Has_Ar
        or else not Has_Cpio
        or else not Has_Iso
        or else not Has_Cab_Unsupported
        or else not Has_Xz_Unsupported
        or else not Has_Xz
        or else not Has_Seven_Zip_Encrypted
        or else not Has_Rar_Unsupported
        or else not Has_Split_Zip_Unsupported
        or else not Has_BZip2
        or else not Has_Zstd
        or else not Has_Zip_Stored or else not Has_Zip_Deflate
        or else not Has_Zip_Descriptor or else not Has_Zip64
        or else not Has_Gzip or else not Has_Gzip_Empty
        or else not Has_Zip_Bad_CRC
        or else not Has_Zip_Central_CRC_Mismatch
        or else not Has_Zip_Unicode_Bad_CRC
        or else not Has_Zip_Unicode_Bad_Version
        or else not Has_Zip_Unsupported or else not Has_Zip_PPMd
        or else not Has_Zip_Encrypted
        or else not Has_Zip64_Missing_Extra
        or else not Has_Zip64_Too_Large
        or else not Has_Zip_Local_Size_Mismatch
        or else not Has_Zip_Bad_Local_Signature
        or else not Has_Zip_Multi_Disk
        or else not Has_Gzip_Bad_Header_CRC
        or else not Has_Gzip_Bad_Trailer
      then
         Invalid := Invalid + 1;
         Put_Line
           (Standard_Error,
            Manifest & ": fixture manifest is missing required release fixtures");
      end if;
   exception
      when others =>
         if Ada.Text_IO.Is_Open (File) then
            Ada.Text_IO.Close (File);
         end if;
         raise;
   end Check_Fixture_Manifest;

   procedure Check_Corpus_Manifest is
      Manifest : constant String := Root & "/tests/fixtures/corpus.txt";
      File     : Ada.Text_IO.File_Type;
      Buffer   : String (1 .. 1024);
      Last     : Natural;
      Line_No  : Natural := 0;
      Count    : Natural := 0;
      Has_Path_Attack : Boolean := False;
      Has_Unsupported_Format : Boolean := False;
      Has_Tar : Boolean := False;
      Has_Tar_Gzip : Boolean := False;
      Has_Zip_Stored : Boolean := False;
      Has_Zip_Deflate : Boolean := False;
      Has_Gzip : Boolean := False;
      Has_Malformed : Boolean := False;
      Has_Platform_Collision : Boolean := False;
      Has_Zip_Unicode : Boolean := False;
      Has_Zip64_Overflow : Boolean := False;
      Has_Zip_Unsupported_Method : Boolean := False;
      Has_Zip_Encrypted : Boolean := False;
      Has_Zip_Multi_Disk : Boolean := False;
      Has_Gzip_Bad_Trailer : Boolean := False;

      procedure Require_Field
        (Line        : String;
         Field       : String;
         Line_Number : Natural)
      is
      begin
         if Field_Value (Line, Field) = "" then
            Invalid := Invalid + 1;
            Put_Line
              (Standard_Error,
               Manifest & ":" & Line_Number'Image
               & ": corpus case is missing " & Field);
         end if;
      end Require_Field;

      function Registered_Fixture_Id (Value : String) return Boolean is
         Fixture_Manifest : constant String := Root & "/tests/fixtures/manifest.txt";
         Fixture_File     : Ada.Text_IO.File_Type;
         Fixture_Buffer   : String (1 .. 1024);
         Fixture_Last     : Natural;
      begin
         if Value = "" or else not Ada.Directories.Exists (Fixture_Manifest) then
            return False;
         end if;

         Ada.Text_IO.Open (Fixture_File, Ada.Text_IO.In_File, Fixture_Manifest);
         while not Ada.Text_IO.End_Of_File (Fixture_File) loop
            Ada.Text_IO.Get_Line (Fixture_File, Fixture_Buffer, Fixture_Last);
            declare
               Fixture_Line : constant String := Fixture_Buffer (1 .. Fixture_Last);
            begin
               if Fixture_Last > 0
                 and then Starts_With (Fixture_Line, "fixture ")
                 and then Field_Value (Fixture_Line, "id") = Value
               then
                  Ada.Text_IO.Close (Fixture_File);
                  return True;
               end if;
            end;
         end loop;
         Ada.Text_IO.Close (Fixture_File);
         return False;
      exception
         when others =>
            if Ada.Text_IO.Is_Open (Fixture_File) then
               Ada.Text_IO.Close (Fixture_File);
            end if;
            return False;
      end Registered_Fixture_Id;

      function Known_Archive_Input (Value : String) return Boolean is
      begin
         return Registered_Fixture_Id (Value);
      end Known_Archive_Input;

      function Known_Format_Input (Value : String) return Boolean is
      begin
         return Value in
           "7z-signature"
           | "zstd-signature"
           | "xz-signature"
           | "bzip2-signature"
           | "rar-signature"
           | "random-bytes"
           | "cab-signature"
           | "cpio-newc-signature"
           | "ar-signature"
           | "split-zip-signature"
           | "iso-signature";
      end Known_Format_Input;

      function Known_Format_Id (Value : String) return Boolean is
      begin
         return Value in
           "Unknown_Format"
           | "Tar_Format"
           | "Tar_Gzip_Format"
           | "Zip_Format"
           | "Gzip_Format"
           | "Seven_Zip_Format"
           | "BZip2_Format"
           | "Zstd_Format"
           | "Xz_Format"
           | "Rar_Format"
           | "Cab_Format"
           | "Cpio_Format"
           | "Iso_Format"
           | "Ar_Format"
           | "Split_Zip_Format";
      end Known_Format_Id;

      function Known_Detection_Status (Value : String) return Boolean is
      begin
         return Value in "Detected" | "Recognized_Unsupported" | "Invalid";
      end Known_Detection_Status;

      function Known_Error_Code (Value : String) return Boolean is
      begin
         return Value in
           "Ok"
           | "Read_Failed"
           | "Write_Failed"
           | "Invalid_Format"
           | "Unsupported_Format"
           | "Unsupported_Method"
           | "Zlib_Failed"
           | "Limit_Exceeded"
           | "Cancelled";
      end Known_Error_Code;

      function Natural_Text (Value : String) return Boolean is
      begin
         if Value = "" then
            return False;
         end if;

         for C of Value loop
            if C not in '0' .. '9' then
               return False;
            end if;
         end loop;

         return True;
      end Natural_Text;

      function Known_Platform (Value : String) return Boolean is
      begin
         return Value in "POSIX" | "Windows" | "MacOS";
      end Known_Platform;

      function Known_Path_Safety (Value : String) return Boolean is
      begin
         return Value in
           "Safe_Path"
           | "Empty_Path"
           | "Parent_Traversal"
           | "Absolute_Path"
           | "Windows_Drive_Path"
           | "Alternate_Data_Stream"
           | "Reserved_Name"
           | "Too_Long";
      end Known_Path_Safety;

      function Known_Path_Decision (Value : String) return Boolean is
      begin
         return Value in
           "Path_Accepted"
           | "Path_Blocked_Empty"
           | "Path_Blocked_Unsafe";
      end Known_Path_Decision;

      function Known_Boolean_Text (Value : String) return Boolean is
      begin
         return Value in "true" | "false";
      end Known_Boolean_Text;

      procedure Reject_Unknown
        (Field       : String;
         Value       : String;
         Known       : Boolean;
         Line_Number : Natural)
      is
      begin
         if Value /= "" and then not Known then
            Invalid := Invalid + 1;
            Put_Line
              (Standard_Error,
               Manifest & ":" & Line_Number'Image
               & ": unknown corpus " & Field & " " & Value);
         end if;
      end Reject_Unknown;
   begin
      if not Ada.Directories.Exists (Manifest) then
         Missing := Missing + 1;
         Put_Line (Standard_Error, Manifest & ": missing corpus manifest");
         return;
      end if;

      Ada.Text_IO.Open (File, Ada.Text_IO.In_File, Manifest);
      while not Ada.Text_IO.End_Of_File (File) loop
         Ada.Text_IO.Get_Line (File, Buffer, Last);
         Line_No := Line_No + 1;

         declare
            Line : constant String := Buffer (1 .. Last);
            Id   : constant String := Field_Value (Line, "id");
            Kind : constant String := Field_Value (Line, "kind");
         begin
            if Last = 0 or else Line (Line'First) = '#' then
               null;
            elsif Starts_With (Line, "case ") then
               Count := Count + 1;
               Require_Field (Line, "id", Line_No);
               Require_Field (Line, "kind", Line_No);

               if Kind = "path" then
                  Require_Field (Line, "input", Line_No);
                  Require_Field (Line, "safety", Line_No);
                  Require_Field (Line, "decision", Line_No);
                  Require_Field (Line, "platform", Line_No);
                  Reject_Unknown
                    ("safety", Field_Value (Line, "safety"),
                     Known_Path_Safety (Field_Value (Line, "safety")), Line_No);
                  Reject_Unknown
                    ("decision", Field_Value (Line, "decision"),
                     Known_Path_Decision (Field_Value (Line, "decision")), Line_No);
                  Reject_Unknown
                    ("platform", Field_Value (Line, "platform"),
                     Known_Platform (Field_Value (Line, "platform")), Line_No);
                  if Field_Value (Line, "decision") = "Path_Blocked_Unsafe" then
                     Has_Path_Attack := True;
                  end if;
               elsif Kind = "platform-key" then
                  Require_Field (Line, "input", Line_No);
                  Require_Field (Line, "expected", Line_No);
                  Require_Field (Line, "platform", Line_No);
                  Reject_Unknown
                    ("platform", Field_Value (Line, "platform"),
                     Known_Platform (Field_Value (Line, "platform")), Line_No);
               elsif Kind = "platform-collision" then
                  Require_Field (Line, "left", Line_No);
                  Require_Field (Line, "right", Line_No);
                  Require_Field (Line, "platform", Line_No);
                  Require_Field (Line, "collision", Line_No);
                  Reject_Unknown
                    ("platform", Field_Value (Line, "platform"),
                     Known_Platform (Field_Value (Line, "platform")), Line_No);
                  Reject_Unknown
                    ("collision", Field_Value (Line, "collision"),
                     Known_Boolean_Text (Field_Value (Line, "collision")), Line_No);
                  Has_Platform_Collision := True;
               elsif Kind = "format" then
                  Require_Field (Line, "input", Line_No);
                  Require_Field (Line, "expected", Line_No);
                  Require_Field (Line, "status", Line_No);
                  Reject_Unknown
                    ("format", Field_Value (Line, "expected"),
                     Known_Format_Id (Field_Value (Line, "expected")), Line_No);
                  Reject_Unknown
                    ("detection status", Field_Value (Line, "status"),
                     Known_Detection_Status (Field_Value (Line, "status")), Line_No);
                  if Field_Value (Line, "input") /= ""
                    and then not Known_Format_Input (Field_Value (Line, "input"))
                  then
                     Invalid := Invalid + 1;
                     Put_Line
                       (Standard_Error,
                        Manifest & ":" & Line_No'Image
                        & ": unknown format corpus input "
                        & Field_Value (Line, "input"));
                  end if;
                  if Field_Value (Line, "status") = "Recognized_Unsupported" then
                     Has_Unsupported_Format := True;
                  end if;
               elsif Kind = "archive" then
                  Require_Field (Line, "input", Line_No);
                  Require_Field (Line, "source", Line_No);
                  Require_Field (Line, "open", Line_No);
                  Require_Field (Line, "entries", Line_No);
                  Reject_Unknown
                    ("open error", Field_Value (Line, "open"),
                     Known_Error_Code (Field_Value (Line, "open")), Line_No);
                  Reject_Unknown
                    ("entries", Field_Value (Line, "entries"),
                     Natural_Text (Field_Value (Line, "entries")), Line_No);
                  Reject_Unknown
                    ("payload error", Field_Value (Line, "payload"),
                     Known_Error_Code (Field_Value (Line, "payload")), Line_No);
                  if Field_Value (Line, "input") /= ""
                    and then not Known_Archive_Input (Field_Value (Line, "input"))
                  then
                     Invalid := Invalid + 1;
                     Put_Line
                       (Standard_Error,
                        Manifest & ":" & Line_No'Image
                        & ": unknown archive corpus input "
                        & Field_Value (Line, "input"));
                  end if;
                  if Id = "archive-tar-basic" then
                     Has_Tar := True;
                  elsif Id = "archive-tar-gzip-basic" then
                     Has_Tar_Gzip := True;
                  elsif Id = "archive-zip-stored-basic" then
                     Has_Zip_Stored := True;
                  elsif Id = "archive-zip-deflate-basic" then
                     Has_Zip_Deflate := True;
                  elsif Id = "archive-gzip-basic" then
                     Has_Gzip := True;
                  elsif Id = "archive-zip-unicode-path" then
                     Has_Zip_Unicode := True;
                  elsif Id = "archive-zip-zip64-too-large" then
                     Has_Zip64_Overflow := True;
                  elsif Id = "archive-zip-truncated-central"
                    or else Id = "archive-gzip-truncated"
                    or else Id = "archive-tar-truncated"
                    or else Id = "archive-zip-bad-crc"
                  then
                     Has_Malformed := True;
                  elsif Id = "archive-zip-unsupported-method" then
                     Has_Zip_Unsupported_Method := True;
                  elsif Id = "archive-zip-encrypted" then
                     Has_Zip_Encrypted := True;
                  elsif Id = "archive-zip-multi-disk" then
                     Has_Zip_Multi_Disk := True;
                  elsif Id = "archive-gzip-bad-trailer" then
                     Has_Gzip_Bad_Trailer := True;
                  end if;
               elsif Kind /= "" then
                  Invalid := Invalid + 1;
                  Put_Line
                    (Standard_Error,
                     Manifest & ":" & Line_No'Image
                     & ": unknown corpus kind " & Kind);
               end if;
            else
               Invalid := Invalid + 1;
               Put_Line
                 (Standard_Error,
                  Manifest & ":" & Line_No'Image & ": unknown corpus record");
            end if;
         end;
      end loop;
      Ada.Text_IO.Close (File);

      if Count < 12 then
         Invalid := Invalid + 1;
         Put_Line (Standard_Error, Manifest & ": corpus manifest has too few cases");
      elsif not Has_Path_Attack or else not Has_Unsupported_Format
        or else not Has_Tar or else not Has_Tar_Gzip or else not Has_Zip_Stored
        or else not Has_Zip_Deflate or else not Has_Gzip or else not Has_Malformed
        or else not Has_Platform_Collision
        or else not Has_Zip_Unicode or else not Has_Zip64_Overflow
        or else not Has_Zip_Unsupported_Method or else not Has_Zip_Encrypted
        or else not Has_Zip_Multi_Disk
        or else not Has_Gzip_Bad_Trailer
      then
         Invalid := Invalid + 1;
         Put_Line
           (Standard_Error,
            Manifest & ": corpus manifest is missing required format/security breadth");
      end if;
   exception
      when others =>
         if Ada.Text_IO.Is_Open (File) then
            Ada.Text_IO.Close (File);
         end if;
         raise;
   end Check_Corpus_Manifest;

   procedure Check_Dependency_License_Manifests is
      procedure Require_Marker (Relative_Path : String; Marker : String) is
         Path : constant String := Root & "/" & Relative_Path;
      begin
         if not Ada.Directories.Exists (Path) then
            Missing := Missing + 1;
            Put_Line (Standard_Error, Path & ": missing dependency/license input");
            return;
         end if;

         declare
            Content : constant String := To_String (Read_Text_File (Path));
         begin
            if not Contains (Content, Marker) then
               Invalid := Invalid + 1;
               Put_Line
                 (Standard_Error,
                  Path & ": missing dependency/license marker: " & Marker);
            end if;
         end;
      end Require_Marker;
   begin
      Require_Marker ("alire.toml", "licenses = ""MIT OR Apache-2.0 WITH LLVM-exception""");
      Require_Marker ("tests/alire.toml", "licenses = ""MIT OR Apache-2.0 WITH LLVM-exception""");
      Require_Marker ("alire.toml", "guikit = ""*""");
      Require_Marker ("alire.toml", "i18n = ""*""");
      Require_Marker ("alire.toml", "messages = ""*""");
      Require_Marker ("alire.toml", "tarlib = ""*""");
      Require_Marker ("alire.toml", "zlib = ""*""");
      Require_Marker ("tests/alire.toml", "archive = ""*""");
      Require_Marker ("tests/alire.toml", "messages = ""*""");
      Require_Marker ("tests/alire.toml", "project_tools = ""*""");
      Require_Marker ("tests/alire.toml", "aunit = ""^26.0.0""");
      Require_Marker ("docs/phase-0-dependency-audit.md", "`project_tools` exposes Ada process");
   end Check_Dependency_License_Manifests;

   procedure Emit_JSON is
   begin
      Put_Line (JSON_Report);
   end Emit_JSON;
begin
   Require_File (Root & "/README.md");
   Require_File (Root & "/alire.toml");
   Require_File (Root & "/archive.gpr");
   Require_File (Root & "/share/archive.catalog");
   --  The load-only i18n serves formatting from data files at runtime, so a
   --  release must bundle them (tools/i18n_bundle, run post-build).
   Require_File (Root & "/share/i18n/formats.i18ndata");
   Require_File (Root & "/docs/IMPLEMENTATION_PLAN.md");
   Require_File (Root & "/docs/FORMAT_SUPPORT.md");
   Require_File (Root & "/docs/check-all-workflow.md");
   Require_File (Root & "/packaging/manifest.txt");
   Require_File (Root & "/tests/proof/archive_release_proof.gpr");
   Require_File (Root & "/tests/proof/src/archive_release_proof.ads");
   Require_File (Root & "/tests/proof/src/archive_release_proof.adb");
   Require_File (Root & "/tests/fixtures/manifest.txt");
   Require_File (Root & "/tests/fixtures/corpus.txt");
   Require_File (Tests & "/archive_tests.gpr");

   Require_Text (".github/workflows/check.yml", "tests/bin/check_all");
   Require_Text ("README.md", "tests/bin/release_report --check");
   Require_Text ("docs/release-guide.md", "Release validation is owned by Ada tooling");
   Require_Text ("docs/release-guide.md", "packaging/manifest.txt");
   Require_Text ("docs/release-guide.md", "dependency/license checks are enforced by Ada tooling");
   Require_Text ("docs/release-guide.md", "release builds are enforced by Ada tooling");
   Require_Text ("docs/release-guide.md", "integration tests are enforced by Ada tooling");
   Require_Text ("docs/release-guide.md", "GNATprove is enforced by Ada tooling");
   Require_Text ("docs/release-guide.md", "per-format completion gate workflow");
   Require_Text ("docs/release-guide.md", "output publication gating");
   Require_Text ("docs/release-guide.md", "packaged smoke tests are enforced by Ada tooling");
   Require_Text ("docs/release-guide.md", "release cleanliness is enforced by Ada tooling");
   Require_Text ("docs/check-all-workflow.md", "full graph release builds");
   Require_Text ("docs/check-all-workflow.md", "project-local GNATprove proof target");
   Require_Text ("docs/check-all-workflow.md", "completion gate format workflow gates");
   Require_Text ("docs/check-all-workflow.md", "progress coalescing count invariants");
   Require_Text ("docs/check-all-workflow.md", "packaged smoke test");
   Require_Text ("docs/check-all-workflow.md", "release cleanliness scan");
   Require_Text ("docs/testing-guide.md", "Tests must not require public network access");
   Require_Text ("docs/fixture-guide.md", "crc32=<eight-hex-digits>");
   Require_Text ("docs/fixture-guide.md", "malformed/security corpus manifest");
   Require_Text ("docs/FORMAT_SUPPORT.md", "ZIP DEFLATE");
   Require_Text ("docs/IMPLEMENTATION_PLAN.md", "Completion Gate");
   Require_Text ("share/archive.catalog", "en.application.title =");
   Require_Text
     ("tests/fixtures/manifest.txt",
      "fixture id=plain-ok path=tests/fixtures/plain-ok.txt");
   Require_Tests_Text ("alire.toml", "release_report");
   Require_Tests_Text ("archive_tests.gpr", "release_report.adb");
   Check_Package_Manifest;
   Check_Fixture_Manifest;
   Check_Corpus_Manifest;
   Check_Dependency_License_Manifests;

   if Ada.Command_Line.Argument_Count >= 2
     and then Ada.Command_Line.Argument (1) = "--write"
   then
      Write_Report (Ada.Command_Line.Argument (2), JSON_Report);
   else
      Emit_JSON;
   end if;

   if Ada.Command_Line.Argument_Count >= 1
     and then (Ada.Command_Line.Argument (1) = "--check"
               or else Ada.Command_Line.Argument (1) = "--write")
     and then not Ready
   then
      Ada.Command_Line.Set_Exit_Status (Ada.Command_Line.Failure);
   end if;
end Release_Report;
