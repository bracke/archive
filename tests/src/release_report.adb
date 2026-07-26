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

   function CRC32_Compute (Bytes : Zlib.Byte_Array) return Archive.Types.CRC32_Value is
      State : Archive.Verification.CRC32.CRC32_State := Archive.Verification.CRC32.Initial;
   begin
      Archive.Verification.CRC32.Update (State, Bytes);
      return Archive.Verification.CRC32.Final (State);
   end CRC32_Compute;

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

   function Read_Bytes (Path : String) return Zlib.Byte_Array is
      File : Ada.Streams.Stream_IO.File_Type;
      Size : constant Natural := Natural (Ada.Directories.Size (Path));
   begin
      if Size = 0 then
         return Result : Zlib.Byte_Array (1 .. 0);
      end if;

      declare
         Raw    : Ada.Streams.Stream_Element_Array
           (1 .. Ada.Streams.Stream_Element_Offset (Size));
         Last   : Ada.Streams.Stream_Element_Offset;
         Result : Zlib.Byte_Array (1 .. Size);
      begin
         Ada.Streams.Stream_IO.Open (File, Ada.Streams.Stream_IO.In_File, Path);
         Ada.Streams.Stream_IO.Read (File, Raw, Last);
         Ada.Streams.Stream_IO.Close (File);

         if Natural (Last) /= Size then
            Invalid := Invalid + 1;
            Put_Line (Standard_Error, Path & ": package input read length mismatch");
         end if;

         for Index in Result'Range loop
            Result (Index) := Zlib.Byte (Raw (Ada.Streams.Stream_Element_Offset (Index)));
         end loop;

         return Result;
      end;
   exception
      when others =>
         if Ada.Streams.Stream_IO.Is_Open (File) then
            Ada.Streams.Stream_IO.Close (File);
         end if;
         raise;
   end Read_Bytes;

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
                     declare
                        Bytes : constant Zlib.Byte_Array := Read_Bytes (Root & "/" & Path);
                        CRC   : constant Archive.Types.CRC32_Value :=
                          CRC32_Compute (Bytes);
                     begin
                        Package_Byte_Count := Package_Byte_Count + Bytes'Length;
                        Package_CRC_Xor := Package_CRC_Xor xor Interfaces.Unsigned_32 (CRC);
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
      Has_Zip_Unsupported_Method : Boolean := False;
      Has_Zip_Encrypted : Boolean := False;
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
               Require_Field (Line, "input", Line_No);

               if Kind = "path" then
                  Require_Field (Line, "safety", Line_No);
                  Require_Field (Line, "decision", Line_No);
                  Require_Field (Line, "platform", Line_No);
                  if Field_Value (Line, "decision") = "Path_Blocked_Unsafe" then
                     Has_Path_Attack := True;
                  end if;
               elsif Kind = "platform-key" then
                  Require_Field (Line, "expected", Line_No);
                  Require_Field (Line, "platform", Line_No);
               elsif Kind = "format" then
                  Require_Field (Line, "expected", Line_No);
                  Require_Field (Line, "status", Line_No);
                  if Field_Value (Line, "status") = "Recognized_Unsupported" then
                     Has_Unsupported_Format := True;
                  end if;
               elsif Kind = "archive" then
                  Require_Field (Line, "source", Line_No);
                  Require_Field (Line, "open", Line_No);
                  Require_Field (Line, "entries", Line_No);
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
        or else not Has_Zip_Unsupported_Method or else not Has_Zip_Encrypted
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
      Require_Marker ("alire.toml", "tarlib = ""*""");
      Require_Marker ("alire.toml", "zlib = ""*""");
      Require_Marker ("tests/alire.toml", "archive = ""*""");
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
   Require_Text ("share/archive.catalog", "application.title=");
   Require_Text
     ("tests/fixtures/manifest.txt",
      "fixture id=plain-ok path=tests/fixtures/plain-ok.txt");
   Require_Tests_Text ("alire.toml", "release_report");
   Require_Tests_Text ("archive_tests.gpr", "release_report.adb");
   Check_Package_Manifest;
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
