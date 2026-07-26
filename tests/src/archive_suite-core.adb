with AUnit;
with AUnit.Assertions;
with AUnit.Test_Cases;

with Ada.Calendar;
with Ada.Containers.Vectors;
with Ada.Directories;
with Ada.Strings.Fixed;
with Ada.Streams.Stream_IO;
with Interfaces;
with Guikit.Input;
with Guikit.Vulkan;
with Archive.Application;
with Archive.Application.Windows;
with Archive.Archives.Capabilities;
with Archive.Archives.Entries;
with Archive.Archives.Errors;
with Archive.Archives.Formats;
with Archive.Archives.Index;
with Archive.Archives.Opening;
with Archive.Archives.Opening.Tasks;
with Archive.Archives.Paths;
with Archive.Archives.Readers.Gzip;
with Archive.Archives.Readers.Dispatch;
with Archive.Archives.Readers.Tar;
with Archive.Archives.Readers.Zip;
with Archive.Archives.Streams;
with Archive.Commands;
with Archive.Compression.Zlib;
with Archive.GUI_Frame;
with Archive.GUI_Runtime;
with Archive.Extraction.Execution;
with Archive.Extraction.Paths;
with Archive.Extraction.Plans;
with Archive.Extraction.Results;
with Archive.Extraction.Service;
with Archive.Model;
with Archive.Localization;
with Archive.Navigation;
with Archive.Operations.Opening;
with Archive.Preview;
with Archive.Preview.Service;
with Archive.Resource_Limits;
with Archive.Selection;
with Archive.Settings;
with Archive.Source_Monitoring;
with Archive.Tasking.Events;
with Archive.Tasking.Queues;
with Archive.Tasking.Services;
with Archive.Tasking.Cancellation;
with Archive.Temporary_Resources;
with Archive.Types;
with Archive.UI;
with Archive.Verification.CRC32;
with Archive.Verification.Archives;
with Archive.Verification.Entries;
with Archive.Verification.Overlays;
with Archive.View_Snapshots;
with Archive.View_Snapshots.Archive_Properties;
with Archive.View_Snapshots.Breadcrumbs;
with Archive.View_Snapshots.Columns;
with Archive.View_Snapshots.Command_Palette;
with Archive.View_Snapshots.Command_Surfaces;
with Archive.View_Snapshots.Entry_Properties;
with Archive.Writes.Execution;
with Archive.Writes.Dispatch;
with Archive.Writes.Plans;
with Archive.Writes.Results;
with Archive.Writes.Service;
with Archive.Writes.Tar;
with Archive.Writes.Zip;
with Ada.Strings.Unbounded;
with Tarlib;
with Tarlib.Entries;
with Tarlib.Errors;
with Tarlib.Outputs;
with Tarlib.Writers;
with Zlib;
with Zlib.BZip2_Encoder;
with Zlib.Zstd_Encoder;

package body Archive_Suite.Core is
   use type Interfaces.Unsigned_32;
   use type Interfaces.Unsigned_64;

   use AUnit.Assertions;
   use type Archive.Application.Run_Mode;
   use type Archive.Archives.Capabilities.Entry_Unavailable_Reason;
   use type Archive.Archives.Formats.Detection_Status;
   use type Archive.Archives.Formats.Format_Id;
   use type Archive.Archives.Entries.Compression_Method;
   use type Archive.Archives.Entries.Encryption_State;
   use type Archive.Archives.Entries.Entry_Kind;
   use type Archive.Archives.Entries.Integrity_State;
   use type Archive.Archives.Entries.Path_Safety;
   use type Archive.Archives.Errors.Error_Code;
   use type Archive.Archives.Index.Index_Status;
   use type Archive.Archives.Opening.Open_Status;
   use type Archive.Commands.Command_Id;
   use type Archive.Commands.Command_Category;
   use type Archive.Compression.Zlib.Stream_Mode;
   use type Archive.Compression.Zlib.Stream_Close_Status;
   use type Archive.Extraction.Results.Extraction_Status;
   use type Archive.Extraction.Results.Plan_Execution_Status;
   use type Archive.Extraction.Service.Extract_Status;
   use type Archive.Operations.Opening.Operation_Status;
   use type Archive.Extraction.Paths.Destination_Decision;
   use type Archive.Extraction.Paths.Path_Decision;
   use type Archive.Extraction.Plans.Plan_Status;
   use type Archive.Resource_Limits.Limit_Value;
   use type Archive.Source_Monitoring.Source_Status;
   use type Archive.Settings.Extraction_Conflict_Policy;
   use type Archive.Settings.Link_Extraction_Policy;
   use type Archive.Tasking.Events.Event_Decision;
   use type Archive.Tasking.Events.Event_Kind;
   use type Archive.Tasking.Queues.Enqueue_Result;
   use type Archive.Tasking.Services.Operation_Owner;
   use type Archive.Temporary_Resources.Cleanup_Decision;
   use type Archive.Temporary_Resources.Resource_Id;
   use type Archive.Temporary_Resources.Resource_State;
   use type Archive.Verification.Overlays.Overlay_Acceptance;
   use type Archive.Writes.Plans.Conflict_Resolution_Action;
   use type Archive.Verification.Overlays.Verification_Phase;
   use type Archive.View_Snapshots.Columns.Column_Id;
   use type Archive.Writes.Plans.Entry_Decision;
   use type Archive.Writes.Plans.Plan_Status;
   use type Archive.Writes.Plans.Write_Action;
   use type Archive.Writes.Results.Write_Status;
   use type Archive.Writes.Service.Save_Status;
   use type Ada.Streams.Stream_Element_Offset;
   use type Ada.Directories.File_Kind;
   use type Archive.Types.Entry_Id;
   use type Archive.Types.Generation_Id;
   use type Archive.Types.Compressed_Size;
   use type Archive.Types.CRC32_Value;
   use type Archive.Types.Uncompressed_Size;
   use type Archive.Model.Lifecycle_State;
   use type Archive.Model.Dialog_Kind;
   use type Archive.Model.Source_Change_State;
   use type Archive.Model.Focus_Region;
   use type Archive.Model.Lifecycle_Request;
   use type Archive.Model.Notification_Severity;
   use type Archive.Model.Overlay_Kind;
   use type Archive.Model.Preview_State;
   use type Archive.Model.Copy_Result_Kind;
   use type Archive.Model.Extraction_State;
   use type Archive.Preview.Preview_Kind;
   use type Archive.Resource_Limits.Validation_Status;
   use type Archive.Types.View_Mode;
   use type Archive.View_Snapshots.Sort_Field;
   use type Archive.View_Snapshots.Sort_Direction;
   use type Tarlib.Errors.Status_Code;
   use type Zlib.Byte;
   use type Zlib.Byte_Array;
   use type Zlib.Status_Code;
   use Ada.Strings.Unbounded;

   type Core_Test_Case is new AUnit.Test_Cases.Test_Case with null record;
   overriding function Name (T : Core_Test_Case) return AUnit.Message_String;
   overriding procedure Register_Tests (T : in out Core_Test_Case);

   procedure Test_Format_Detection (T : in out AUnit.Test_Cases.Test_Case'Class);
   procedure Test_Zip_Index (T : in out AUnit.Test_Cases.Test_Case'Class);
   procedure Test_Gzip_Reader (T : in out AUnit.Test_Cases.Test_Case'Class);
   procedure Test_Zlib_Adapter_Limits (T : in out AUnit.Test_Cases.Test_Case'Class);
   procedure Test_Reader_Dispatch (T : in out AUnit.Test_Cases.Test_Case'Class);
   procedure Test_CRC32 (T : in out AUnit.Test_Cases.Test_Case'Class);
   procedure Test_Preview (T : in out AUnit.Test_Cases.Test_Case'Class);
   procedure Test_Preview_Service (T : in out AUnit.Test_Cases.Test_Case'Class);
   procedure Test_Path_Safety (T : in out AUnit.Test_Cases.Test_Case'Class);
   procedure Test_Immutable_Index (T : in out AUnit.Test_Cases.Test_Case'Class);
   procedure Test_View_Projection (T : in out AUnit.Test_Cases.Test_Case'Class);
   procedure Test_Details_Columns (T : in out AUnit.Test_Cases.Test_Case'Class);
   procedure Test_Property_Snapshots (T : in out AUnit.Test_Cases.Test_Case'Class);
   procedure Test_Extraction_Planning (T : in out AUnit.Test_Cases.Test_Case'Class);
   procedure Test_Extraction_Security_Gate (T : in out AUnit.Test_Cases.Test_Case'Class);
   procedure Test_Write_Planning (T : in out AUnit.Test_Cases.Test_Case'Class);
   procedure Test_Deterministic_Mutation_Gate (T : in out AUnit.Test_Cases.Test_Case'Class);
   procedure Test_Write_Execution (T : in out AUnit.Test_Cases.Test_Case'Class);
   procedure Test_Tar_Write_Adapter (T : in out AUnit.Test_Cases.Test_Case'Class);
   procedure Test_Gzip_Write_Adapters (T : in out AUnit.Test_Cases.Test_Case'Class);
   procedure Test_Zip_Write_Adapter (T : in out AUnit.Test_Cases.Test_Case'Class);
   procedure Test_Write_Dispatch (T : in out AUnit.Test_Cases.Test_Case'Class);
   procedure Test_Write_Service (T : in out AUnit.Test_Cases.Test_Case'Class);
   procedure Test_Extraction_Execution (T : in out AUnit.Test_Cases.Test_Case'Class);
   procedure Test_Zip_Extract_Workflow (T : in out AUnit.Test_Cases.Test_Case'Class);
   procedure Test_Completion_Gate_Workflows (T : in out AUnit.Test_Cases.Test_Case'Class);
   function Read_All_Bytes (Path : String) return Zlib.Byte_Array;
   procedure Write_Bytes (Path : String; Bytes : Zlib.Byte_Array);
   function CRC32_Compute (Bytes : Zlib.Byte_Array) return Archive.Types.CRC32_Value;
   function Fixture_Path
     (Name  : String;
      Bytes : Zlib.Byte_Array)
      return String;
   function Detect_Bytes
     (Bytes : Zlib.Byte_Array)
      return Archive.Archives.Formats.Detection_Result;
   function Index_Zip
     (Bytes : Zlib.Byte_Array)
      return Archive.Archives.Readers.Zip.Zip_Index_Result;
   function Index_Tar
     (Bytes : Zlib.Byte_Array)
      return Archive.Archives.Readers.Tar.Tar_Index_Result;
   function Index_Gzip
     (Bytes       : Zlib.Byte_Array;
      Source_Name : String := "")
      return Archive.Archives.Readers.Gzip.Gzip_Index_Result;
   function Open_Dispatch
     (Bytes       : Zlib.Byte_Array;
      Source_Name : String := "")
      return Archive.Archives.Readers.Dispatch.Open_Result;
   package Test_Byte_Vectors is new Ada.Containers.Vectors
     (Index_Type => Positive,
      Element_Type => Zlib.Byte);

   type Test_Zlib_Result is record
      Status : Archive.Archives.Errors.Error_Code := Archive.Archives.Errors.Ok;
      Compressed_Bytes   : Archive.Types.Compressed_Size := 0;
      Uncompressed_Bytes : Archive.Types.Uncompressed_Size := 0;
      Input_Bytes        : Archive.Types.Uncompressed_Size := 0;
      Output_Bytes       : Archive.Types.Compressed_Size := 0;
      Input_Chunks       : Natural := 0;
      Output_Chunks      : Natural := 0;
      Unused_Input_Bytes : Archive.Types.Compressed_Size := 0;
      Stream_Ended       : Boolean := False;
      Output_Limited     : Boolean := False;
      Ratio_Limited      : Boolean := False;
      Cancelled          : Boolean := False;
      Bytes              : Test_Byte_Vectors.Vector;
   end record;

   function Byte_Vector (Bytes : Zlib.Byte_Array) return Test_Byte_Vectors.Vector;
   function Bytes_Of (Result : Test_Zlib_Result) return Zlib.Byte_Array;
   function Byte_Length (Result : Test_Zlib_Result) return Natural;
   function Byte_Length
     (Result : Archive.Archives.Streams.Buffered_Source)
      return Natural;
   function Byte_Length
     (Result : Archive.Source_Monitoring.Probe_Result)
      return Natural;
   function Test_Inflate
     (Input : Zlib.Byte_Array;
      Mode  : Archive.Compression.Zlib.Stream_Mode;
      Limits : Archive.Compression.Zlib.Inflate_Limits := (others => <>);
      Cancellation : access Archive.Tasking.Cancellation.Token := null)
      return Test_Zlib_Result;
   function Test_Inflate_Streaming
     (Input : Zlib.Byte_Array;
      Mode  : Archive.Compression.Zlib.Stream_Mode;
      Limits : Archive.Compression.Zlib.Inflate_Limits := (others => <>);
      Input_Chunk_Bytes  : Positive := 1_024;
      Output_Chunk_Bytes : Positive := 1_024;
      Cancellation : access Archive.Tasking.Cancellation.Token := null)
      return Test_Zlib_Result;
   function Test_Deflate
     (Input : Zlib.Byte_Array;
      Mode  : Archive.Compression.Zlib.Stream_Mode;
      Max_Output_Bytes : Archive.Types.Compressed_Size :=
        Archive.Types.Compressed_Size
          (Archive.Resource_Limits.Default_Configured
             (Archive.Resource_Limits.Temporary_Backing_Bytes));
      Cancellation : access Archive.Tasking.Cancellation.Token := null)
      return Test_Zlib_Result;
   function Test_Deflate_Streaming
     (Input : Zlib.Byte_Array;
      Mode  : Archive.Compression.Zlib.Stream_Mode;
      Max_Output_Bytes : Archive.Types.Compressed_Size :=
        Archive.Types.Compressed_Size
          (Archive.Resource_Limits.Default_Configured
             (Archive.Resource_Limits.Temporary_Backing_Bytes));
      Input_Chunk_Bytes  : Positive := 1_024;
      Output_Chunk_Bytes : Positive := 1_024;
      Cancellation : access Archive.Tasking.Cancellation.Token := null)
      return Test_Zlib_Result;
   Test_Stream_Prefix_Limit : constant Natural := 16;
   type Test_Stream_Result is record
      Status    : Archive.Archives.Errors.Error_Code := Archive.Archives.Errors.Ok;
      Integrity : Archive.Archives.Entries.Integrity_State :=
        Archive.Archives.Entries.Not_Checked;
      Bytes_Written : Natural := 0;
      Prefix_Length : Natural := 0;
      Bytes     : Zlib.Byte_Array (1 .. Test_Stream_Prefix_Limit) := [others => 0];
   end record;
   function Bytes_Of (Result : Test_Stream_Result) return Zlib.Byte_Array;
   function Byte_Length (Result : Test_Stream_Result) return Natural;
   function Stream_Dispatch_Payload_File
     (Path        : String;
      Source_Name : String;
      Item        : Archive.Archives.Entries.Archive_Entry)
      return Test_Stream_Result;
   function Stream_Dispatch_Payload
     (Bytes       : Zlib.Byte_Array;
      Source_Name : String;
      Item        : Archive.Archives.Entries.Archive_Entry)
      return Test_Stream_Result;
   function Stream_Zip_Payload_File
     (Path : String;
      Item : Archive.Archives.Entries.Archive_Entry)
      return Test_Stream_Result;
   function Stream_Zip_Payload
     (Bytes : Zlib.Byte_Array;
      Item  : Archive.Archives.Entries.Archive_Entry)
      return Test_Stream_Result;
   function Stream_Tar_Payload_File
     (Path : String;
      Item : Archive.Archives.Entries.Archive_Entry)
      return Test_Stream_Result;
   function Stream_Tar_Payload
     (Bytes : Zlib.Byte_Array;
      Item  : Archive.Archives.Entries.Archive_Entry)
      return Test_Stream_Result;
   function Stream_Gzip_Payload
     (Bytes : Zlib.Byte_Array;
      Item  : Archive.Archives.Entries.Archive_Entry)
      return Test_Stream_Result;
   procedure Test_Format_Extract_Workflows (T : in out AUnit.Test_Cases.Test_Case'Class);
   procedure Test_Extraction_Service (T : in out AUnit.Test_Cases.Test_Case'Class);
   procedure Test_Open_Workflow (T : in out AUnit.Test_Cases.Test_Case'Class);
   procedure Test_Open_Task (T : in out AUnit.Test_Cases.Test_Case'Class);
   procedure Test_Open_Coordinator (T : in out AUnit.Test_Cases.Test_Case'Class);
   procedure Test_Source_Monitoring (T : in out AUnit.Test_Cases.Test_Case'Class);
   procedure Test_Stale_Events (T : in out AUnit.Test_Cases.Test_Case'Class);
   procedure Test_Entry_Verification (T : in out AUnit.Test_Cases.Test_Case'Class);
   procedure Test_Full_Archive_Verification (T : in out AUnit.Test_Cases.Test_Case'Class);
   procedure Test_Verification_Overlay (T : in out AUnit.Test_Cases.Test_Case'Class);
   procedure Test_Cancellation (T : in out AUnit.Test_Cases.Test_Case'Class);
   procedure Test_Bounded_Event_Queue (T : in out AUnit.Test_Cases.Test_Case'Class);
   procedure Test_Tasking_Service_Bridge (T : in out AUnit.Test_Cases.Test_Case'Class);
   procedure Test_Temporary_Resources (T : in out AUnit.Test_Cases.Test_Case'Class);
   procedure Test_Selection (T : in out AUnit.Test_Cases.Test_Case'Class);
   procedure Test_Navigation (T : in out AUnit.Test_Cases.Test_Case'Class);
   procedure Test_Breadcrumb_Snapshot (T : in out AUnit.Test_Cases.Test_Case'Class);
   procedure Test_Command_Model (T : in out AUnit.Test_Cases.Test_Case'Class);
   procedure Test_Command_Palette_Snapshot (T : in out AUnit.Test_Cases.Test_Case'Class);
   procedure Test_Command_Surface_Snapshots (T : in out AUnit.Test_Cases.Test_Case'Class);
   procedure Test_UI_Shell (T : in out AUnit.Test_Cases.Test_Case'Class);
   procedure Test_GUI_Frame (T : in out AUnit.Test_Cases.Test_Case'Class);
   procedure Test_GUI_Runtime (T : in out AUnit.Test_Cases.Test_Case'Class);
   procedure Test_Live_Runtime (T : in out AUnit.Test_Cases.Test_Case'Class);
   procedure Test_Settings (T : in out AUnit.Test_Cases.Test_Case'Class);
   procedure Test_Resource_Limits (T : in out AUnit.Test_Cases.Test_Case'Class);
   procedure Test_Localization (T : in out AUnit.Test_Cases.Test_Case'Class);

   overriding function Name (T : Core_Test_Case) return AUnit.Message_String is
      pragma Unreferenced (T);
   begin
      return AUnit.Format ("archive foundational behavior");
   end Name;

   type Memory_Tar_Sink is limited new Tarlib.Outputs.Output_Sink with record
      Buffer : Ada.Streams.Stream_Element_Array (1 .. 8192) := [others => 0];
      Length : Ada.Streams.Stream_Element_Offset := 0;
   end record;

   overriding procedure Write
     (Sink   : in out Memory_Tar_Sink;
      Data   : Ada.Streams.Stream_Element_Array;
      Result : out Tarlib.Errors.Status);

   overriding procedure Write
     (Sink   : in out Memory_Tar_Sink;
      Data   : Ada.Streams.Stream_Element_Array;
      Result : out Tarlib.Errors.Status)
   is
   begin
      if Sink.Length + Ada.Streams.Stream_Element_Offset (Data'Length) > Sink.Buffer'Last then
         Result := (Code => Tarlib.Errors.Output_Failure);
         return;
      end if;

      for Index in Data'Range loop
         Sink.Length := Sink.Length + Ada.Streams.Stream_Element_Offset (1);
         Sink.Buffer (Sink.Length) := Data (Index);
      end loop;
      Result := Tarlib.Errors.OK;
   end Write;

   function Tar_Sink_Bytes (Sink : Memory_Tar_Sink) return Zlib.Byte_Array is
      Result : Zlib.Byte_Array (1 .. Natural (Sink.Length));
   begin
      for Index in Result'Range loop
         Result (Index) := Zlib.Byte (Sink.Buffer (Ada.Streams.Stream_Element_Offset (Index)));
      end loop;
      return Result;
   end Tar_Sink_Bytes;

   function One_File_Tar return Zlib.Byte_Array is
      Sink   : aliased Memory_Tar_Sink;
      Writer : Tarlib.Writers.Writer;
      Status : Tarlib.Errors.Status;
      Data   : constant Ada.Streams.Stream_Element_Array :=
        [1 => Ada.Streams.Stream_Element (Character'Pos ('o')),
         2 => Ada.Streams.Stream_Element (Character'Pos ('k'))];
   begin
      Tarlib.Writers.Initialize (Writer, Sink, Status);
      Assert (Status.Code = Tarlib.Errors.Success, "tar fixture writer initializes");
      Tarlib.Writers.Begin_File (Writer, "docs/readme.txt", Tarlib.Byte_Count (Data'Length), Status);
      Assert (Status.Code = Tarlib.Errors.Success, "tar fixture begins file");
      Tarlib.Writers.Write (Writer, Data, Status);
      Assert (Status.Code = Tarlib.Errors.Success, "tar fixture writes file");
      Tarlib.Writers.End_Entry (Writer, Status);
      Assert (Status.Code = Tarlib.Errors.Success, "tar fixture ends file");
      Tarlib.Writers.Finish (Writer, Status);
      Assert (Status.Code = Tarlib.Errors.Success, "tar fixture finishes archive");

      return Tar_Sink_Bytes (Sink);
   end One_File_Tar;

   overriding procedure Register_Tests (T : in out Core_Test_Case) is
   begin
      AUnit.Test_Cases.Registration.Register_Routine (T, Test_Format_Detection'Access, "format detection");
      AUnit.Test_Cases.Registration.Register_Routine (T, Test_Zip_Index'Access, "zip central directory index");
      AUnit.Test_Cases.Registration.Register_Routine (T, Test_Gzip_Reader'Access, "gzip logical archive reader");
      AUnit.Test_Cases.Registration.Register_Routine
        (T, Test_Zlib_Adapter_Limits'Access, "zlib adapter limits and cancellation");
      AUnit.Test_Cases.Registration.Register_Routine
        (T, Test_Reader_Dispatch'Access, "reader dispatch to immutable index");
      AUnit.Test_Cases.Registration.Register_Routine (T, Test_CRC32'Access, "crc32 verification primitive");
      AUnit.Test_Cases.Registration.Register_Routine (T, Test_Preview'Access, "bounded preview generation");
      AUnit.Test_Cases.Registration.Register_Routine (T, Test_Preview_Service'Access, "preview stale rejection");
      AUnit.Test_Cases.Registration.Register_Routine (T, Test_Path_Safety'Access, "path safety");
      AUnit.Test_Cases.Registration.Register_Routine (T, Test_Immutable_Index'Access, "immutable index");
      AUnit.Test_Cases.Registration.Register_Routine (T, Test_View_Projection'Access, "view projection");
      AUnit.Test_Cases.Registration.Register_Routine (T, Test_Details_Columns'Access, "details column registry");
      AUnit.Test_Cases.Registration.Register_Routine
        (T, Test_Property_Snapshots'Access, "archive and entry property snapshots");
      AUnit.Test_Cases.Registration.Register_Routine (T, Test_Extraction_Planning'Access, "extraction planning");
      AUnit.Test_Cases.Registration.Register_Routine
        (T, Test_Extraction_Security_Gate'Access, "extraction security gate");
      AUnit.Test_Cases.Registration.Register_Routine (T, Test_Write_Planning'Access, "archive write planning");
      AUnit.Test_Cases.Registration.Register_Routine
        (T, Test_Deterministic_Mutation_Gate'Access, "deterministic mutation gate");
      AUnit.Test_Cases.Registration.Register_Routine (T, Test_Write_Execution'Access, "archive write execution");
      AUnit.Test_Cases.Registration.Register_Routine (T, Test_Tar_Write_Adapter'Access, "tar write adapter");
      AUnit.Test_Cases.Registration.Register_Routine
        (T, Test_Gzip_Write_Adapters'Access, "gzip and tar.gz write adapters");
      AUnit.Test_Cases.Registration.Register_Routine (T, Test_Zip_Write_Adapter'Access, "zip write adapter");
      AUnit.Test_Cases.Registration.Register_Routine (T, Test_Write_Dispatch'Access, "write dispatch");
      AUnit.Test_Cases.Registration.Register_Routine (T, Test_Write_Service'Access, "write service");
      AUnit.Test_Cases.Registration.Register_Routine (T, Test_Extraction_Execution'Access, "extraction execution");
      AUnit.Test_Cases.Registration.Register_Routine (T, Test_Zip_Extract_Workflow'Access, "zip extract workflow");
      AUnit.Test_Cases.Registration.Register_Routine
        (T, Test_Format_Extract_Workflows'Access, "format extract workflows");
      AUnit.Test_Cases.Registration.Register_Routine
        (T, Test_Completion_Gate_Workflows'Access, "completion gate format workflows");
      AUnit.Test_Cases.Registration.Register_Routine
        (T, Test_Extraction_Service'Access, "extraction service");
      AUnit.Test_Cases.Registration.Register_Routine (T, Test_Open_Workflow'Access, "archive open workflow");
      AUnit.Test_Cases.Registration.Register_Routine (T, Test_Open_Task'Access, "archive open task");
      AUnit.Test_Cases.Registration.Register_Routine
        (T, Test_Open_Coordinator'Access, "archive open coordinator");
      AUnit.Test_Cases.Registration.Register_Routine (T, Test_Source_Monitoring'Access, "source monitoring");
      AUnit.Test_Cases.Registration.Register_Routine (T, Test_Stale_Events'Access, "stale event rejection");
      AUnit.Test_Cases.Registration.Register_Routine
        (T, Test_Entry_Verification'Access, "entry verification");
      AUnit.Test_Cases.Registration.Register_Routine
        (T, Test_Full_Archive_Verification'Access, "full archive verification");
      AUnit.Test_Cases.Registration.Register_Routine
        (T, Test_Verification_Overlay'Access, "verification overlay");
      AUnit.Test_Cases.Registration.Register_Routine (T, Test_Cancellation'Access, "cancellation token");
      AUnit.Test_Cases.Registration.Register_Routine (T, Test_Bounded_Event_Queue'Access, "bounded event queue");
      AUnit.Test_Cases.Registration.Register_Routine
        (T, Test_Tasking_Service_Bridge'Access, "tasking service bridge");
      AUnit.Test_Cases.Registration.Register_Routine
        (T, Test_Temporary_Resources'Access, "temporary resource registry");
      AUnit.Test_Cases.Registration.Register_Routine (T, Test_Selection'Access, "entry-id selection");
      AUnit.Test_Cases.Registration.Register_Routine (T, Test_Navigation'Access, "navigation history");
      AUnit.Test_Cases.Registration.Register_Routine (T, Test_Breadcrumb_Snapshot'Access, "breadcrumb snapshot");
      AUnit.Test_Cases.Registration.Register_Routine (T, Test_Command_Model'Access, "command model");
      AUnit.Test_Cases.Registration.Register_Routine
        (T, Test_Command_Palette_Snapshot'Access, "command palette snapshot");
      AUnit.Test_Cases.Registration.Register_Routine
        (T, Test_Command_Surface_Snapshots'Access, "command surface snapshots");
      AUnit.Test_Cases.Registration.Register_Routine (T, Test_UI_Shell'Access, "ui shell snapshot");
      AUnit.Test_Cases.Registration.Register_Routine (T, Test_GUI_Frame'Access, "gui frame renderer");
      AUnit.Test_Cases.Registration.Register_Routine (T, Test_GUI_Runtime'Access, "gui runtime shell");
      AUnit.Test_Cases.Registration.Register_Routine (T, Test_Live_Runtime'Access, "live desktop runtime");
      AUnit.Test_Cases.Registration.Register_Routine (T, Test_Settings'Access, "settings defaults");
      AUnit.Test_Cases.Registration.Register_Routine (T, Test_Resource_Limits'Access, "resource limits");
      AUnit.Test_Cases.Registration.Register_Routine (T, Test_Localization'Access, "localization facade");
   end Register_Tests;

   procedure Test_Format_Detection (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      Zip : constant Zlib.Byte_Array := [1 => 16#50#, 2 => 16#4B#, 3 => 16#03#, 4 => 16#04#];
      Gz  : constant Zlib.Byte_Array := [1 => 16#1F#, 2 => 16#8B#, 3 => 16#08#, 4 => 16#00#];
      Seven : constant Zlib.Byte_Array :=
        [1 => 16#37#, 2 => 16#7A#, 3 => 16#BC#, 4 => 16#AF#, 5 => 16#27#, 6 => 16#1C#];
      Bz : constant Zlib.Byte_Array :=
        [1 => Character'Pos ('B'), 2 => Character'Pos ('Z'), 3 => Character'Pos ('h')];
      Zstd : constant Zlib.Byte_Array :=
        [1 => 16#28#, 2 => 16#B5#, 3 => 16#2F#, 4 => 16#FD#];
      Cab : constant Zlib.Byte_Array :=
        [1 => Character'Pos ('M'), 2 => Character'Pos ('S'),
         3 => Character'Pos ('C'), 4 => Character'Pos ('F')];
      Cpio : constant Zlib.Byte_Array :=
        [1 => Character'Pos ('0'), 2 => Character'Pos ('7'),
         3 => Character'Pos ('0'), 4 => Character'Pos ('7'),
         5 => Character'Pos ('0'), 6 => Character'Pos ('1')];
      Ar : constant Zlib.Byte_Array :=
        [1 => Character'Pos ('!'), 2 => Character'Pos ('<'),
         3 => Character'Pos ('a'), 4 => Character'Pos ('r'),
         5 => Character'Pos ('c'), 6 => Character'Pos ('h'),
         7 => Character'Pos ('>'), 8 => 16#0A#];
      Split_Zip : constant Zlib.Byte_Array := [1 => 16#50#, 2 => 16#4B#, 3 => 16#07#, 4 => 16#08#];
      Tar_Bytes : constant Zlib.Byte_Array := One_File_Tar;
      R : Archive.Archives.Formats.Detection_Result;
   begin
      R := Detect_Bytes (Zip);
      Assert (R.Status = Archive.Archives.Formats.Detected, "zip signature detected");
      Assert (R.Format = Archive.Archives.Formats.Zip_Format, "zip format id");

      R := Detect_Bytes (Gz);
      Assert (R.Status = Archive.Archives.Formats.Detected, "gzip signature detected");
      Assert (R.Format = Archive.Archives.Formats.GZip_Format, "gzip format id");

      R := Detect_Bytes (Seven);
      Assert
        (R.Status = Archive.Archives.Formats.Detected,
         "7z signature is detected for the supported zlib-backed subset");
      Assert (R.Format = Archive.Archives.Formats.Seven_Zip_Format, "7z format id");

      R := Detect_Bytes (Bz);
      Assert
        (R.Status = Archive.Archives.Formats.Detected,
         "bzip2 signature is detected for the supported zlib-backed single-file reader");
      Assert (R.Format = Archive.Archives.Formats.BZip2_Format, "bzip2 format id");

      R := Detect_Bytes (Zstd);
      Assert
        (R.Status = Archive.Archives.Formats.Detected,
         "zstd signature is detected for the supported zlib-backed single-file reader");
      Assert (R.Format = Archive.Archives.Formats.Zstd_Format, "zstd format id");

      R := Detect_Bytes (Cab);
      Assert (R.Format = Archive.Archives.Formats.Cab_Format, "cab unsupported format id");

      R := Detect_Bytes (Cpio);
      Assert (R.Format = Archive.Archives.Formats.Cpio_Format, "cpio unsupported format id");

      R := Detect_Bytes (Ar);
      Assert (R.Format = Archive.Archives.Formats.Ar_Format, "ar unsupported format id");

      R := Detect_Bytes (Split_Zip);
      Assert
        (R.Status = Archive.Archives.Formats.Recognized_Unsupported,
         "split zip marker is recognized but unsupported");
      Assert (R.Format = Archive.Archives.Formats.Split_Zip_Format, "split zip unsupported format id");

      R := Detect_Bytes (Tar_Bytes);
      Assert (R.Status = Archive.Archives.Formats.Detected, "tarlib-generated tar is detected");
      Assert (R.Format = Archive.Archives.Formats.Tar_Format, "tar format id");

      declare
         Tar_Caps : constant Archive.Archives.Formats.Format_Capabilities :=
           Archive.Archives.Formats.Capabilities (Archive.Archives.Formats.Tar_Format);
         Zip : constant Archive.Archives.Formats.Format_Capabilities :=
           Archive.Archives.Formats.Capabilities (Archive.Archives.Formats.Zip_Format);
         Gzip : constant Archive.Archives.Formats.Format_Capabilities :=
           Archive.Archives.Formats.Capabilities (Archive.Archives.Formats.GZip_Format);
         Bzip2 : constant Archive.Archives.Formats.Format_Capabilities :=
           Archive.Archives.Formats.Capabilities (Archive.Archives.Formats.BZip2_Format);
         Zstd_Caps : constant Archive.Archives.Formats.Format_Capabilities :=
           Archive.Archives.Formats.Capabilities (Archive.Archives.Formats.Zstd_Format);
         Xz : constant Archive.Archives.Formats.Format_Capabilities :=
           Archive.Archives.Formats.Capabilities (Archive.Archives.Formats.Xz_Format);
      begin
         Assert (Tar_Caps.Can_Create and then Tar_Caps.Can_Add_Entries, "tar exposes write capability");
         Assert (Zip.Can_Create and then Zip.Supports_Random_Access, "zip exposes write capability");
         Assert (Gzip.Can_Create and then not Gzip.Can_Add_Entries,
                 "gzip supports single logical-file creation only");
         Assert (Bzip2.Can_Create and then not Bzip2.Can_Add_Entries,
                 "bzip2 supports single logical-file creation only");
         Assert (Zstd_Caps.Can_Create and then not Zstd_Caps.Can_Add_Entries,
                 "zstd supports single logical-file creation only");
         Assert (not Xz.Can_Create and then not Xz.Can_Index,
                 "unsupported formats do not advertise write capability");
         Assert
           (Archive.Archives.Formats.Description_Key (Archive.Archives.Formats.Zip_Format) =
            "format.zip.description",
            "format description key is derived from stable id");
         Assert
           (Archive.Archives.Formats.Extension_Hints (Archive.Archives.Formats.Tar_GZip_Format) =
            ".tar.gz;.tgz",
            "format extension hints are registry-owned");
      end;
   end Test_Format_Detection;

   procedure Put16 (Bytes : in out Zlib.Byte_Array; Offset : Natural; Value : Natural) is
   begin
      Bytes (Bytes'First + Offset) := Zlib.Byte (Value mod 256);
      Bytes (Bytes'First + Offset + 1) := Zlib.Byte ((Value / 256) mod 256);
   end Put16;

   procedure Put32_U
     (Bytes  : in out Zlib.Byte_Array;
      Offset : Natural;
      Value  : Interfaces.Unsigned_32)
   is
   begin
      Bytes (Bytes'First + Offset) := Zlib.Byte (Value mod 256);
      Bytes (Bytes'First + Offset + 1) := Zlib.Byte ((Value / 256) mod 256);
      Bytes (Bytes'First + Offset + 2) := Zlib.Byte ((Value / 65_536) mod 256);
      Bytes (Bytes'First + Offset + 3) := Zlib.Byte ((Value / 16_777_216) mod 256);
   end Put32_U;

   procedure Put32 (Bytes : in out Zlib.Byte_Array; Offset : Natural; Value : Natural) is
   begin
      Put32_U (Bytes, Offset, Interfaces.Unsigned_32 (Value));
   end Put32;

   procedure Put64 (Bytes : in out Zlib.Byte_Array; Offset : Natural; Value : Natural) is
      Wide : constant Interfaces.Unsigned_64 := Interfaces.Unsigned_64 (Value);
      Low  : constant Interfaces.Unsigned_32 :=
        Interfaces.Unsigned_32 (Wide and 16#FFFF_FFFF#);
      High : constant Interfaces.Unsigned_32 :=
        Interfaces.Unsigned_32 (Interfaces.Shift_Right (Wide, 32));
   begin
      Put32_U (Bytes, Offset, Low);
      Put32_U (Bytes, Offset + 4, High);
   end Put64;

   procedure Put64_U
     (Bytes  : in out Zlib.Byte_Array;
      Offset : Natural;
      Value  : Interfaces.Unsigned_64)
   is
      Low  : constant Interfaces.Unsigned_32 :=
        Interfaces.Unsigned_32 (Value and 16#FFFF_FFFF#);
      High : constant Interfaces.Unsigned_32 :=
        Interfaces.Unsigned_32 (Interfaces.Shift_Right (Value, 32));
   begin
      Put32_U (Bytes, Offset, Low);
      Put32_U (Bytes, Offset + 4, High);
   end Put64_U;

   procedure Put_Text (Bytes : in out Zlib.Byte_Array; Offset : Natural; Text : String) is
   begin
      for Index in Text'Range loop
         Bytes (Bytes'First + Offset + Index - Text'First) := Zlib.Byte (Character'Pos (Text (Index)));
      end loop;
   end Put_Text;

   function CRC32_Text (Text : String) return Interfaces.Unsigned_32 is
      Bytes : Zlib.Byte_Array (1 .. Text'Length);
   begin
      for Index in Text'Range loop
         Bytes (Index - Text'First + 1) := Zlib.Byte (Character'Pos (Text (Index)));
      end loop;
      return Interfaces.Unsigned_32 (CRC32_Compute (Bytes));
   end CRC32_Text;

   function Empty_Zip return Zlib.Byte_Array is
      Bytes : Zlib.Byte_Array (1 .. 22) := [others => 0];
   begin
      Put32 (Bytes, 0, 16#0605_4B50#);
      return Bytes;
   end Empty_Zip;

   function One_File_Zip
     (Method    : Natural := 0;
      Encrypted : Boolean := False;
      Bad_Local_Name : Boolean := False;
      Bad_CRC : Boolean := False;
      Data_Descriptor : Boolean := False;
      Bad_Data_Descriptor : Boolean := False;
      Bad_Local_Size : Boolean := False;
      Local_Extra_Length : Natural := 0;
      Central_Extra_Length : Natural := 0;
      Central_Comment_Length : Natural := 0;
      Archive_Comment_Length : Natural := 0;
      Zip64_Size_Markers : Boolean := False;
      Zip64_Locator : Boolean := False;
      Unicode_Path_Extra : Boolean := False;
      Bad_Unicode_Path_CRC : Boolean := False;
      Bad_Unicode_Path_Version : Boolean := False;
      Descriptor_Signature : Boolean := True;
      Descriptor_Zip64 : Boolean := False;
      Zip64_Extra : Boolean := False;
      Zip64_Too_Large : Boolean := False)
      return Zlib.Byte_Array
   is
      Name : constant String := "a.txt";
      Unicode_Name : constant String := "unicode.txt";
      Plain : constant Zlib.Byte_Array :=
        [1 => Zlib.Byte (Character'Pos ('a')),
         2 => Zlib.Byte (Character'Pos ('b')),
         3 => Zlib.Byte (Character'Pos ('c'))];

      function Build (Payload : Zlib.Byte_Array) return Zlib.Byte_Array is
         Local_Offset : constant Natural := 0;
         ZIP64_Local_Extra_Length : constant Natural := (if Zip64_Extra then 4 + 16 else 0);
         ZIP64_Central_Extra_Length : constant Natural := (if Zip64_Extra then 4 + 16 else 0);
         Effective_Local_Extra : constant Natural := Local_Extra_Length + ZIP64_Local_Extra_Length;
         Effective_Central_Extra : constant Natural :=
           Central_Extra_Length
           + (if Unicode_Path_Extra then 4 + 5 + Unicode_Name'Length else 0)
           + ZIP64_Central_Extra_Length;
         Descriptor_Length : constant Natural :=
           (if Data_Descriptor
            then
              (if Descriptor_Zip64
               then (if Descriptor_Signature then 24 else 20)
               else (if Descriptor_Signature then 16 else 12))
            else 0);
         Central_Offset : constant Natural :=
           30 + Name'Length + Effective_Local_Extra + Payload'Length + Descriptor_Length;
         Central_Size : constant Natural :=
           46 + Name'Length + Effective_Central_Extra + Central_Comment_Length;
         ZIP64_Locator_Length : constant Natural := (if Zip64_Locator then 20 else 0);
         EOCD_Offset : constant Natural := Central_Offset + Central_Size + ZIP64_Locator_Length;
         Total : constant Natural := EOCD_Offset + 22 + Archive_Comment_Length;
         Flags : constant Natural :=
           (if Encrypted then 1 else 0) + (if Data_Descriptor then 8 else 0);
         Bytes : Zlib.Byte_Array (1 .. Total) := [others => 0];
         Local_Size_Value : constant Interfaces.Unsigned_32 :=
           (if Data_Descriptor then 0
            elsif Zip64_Extra then 16#FFFF_FFFF#
            elsif Bad_Local_Size then Interfaces.Unsigned_32 (Payload'Length + 1)
            else Interfaces.Unsigned_32 (Payload'Length));
         Local_Uncompressed_Value : constant Interfaces.Unsigned_32 :=
           (if Data_Descriptor then 0
            elsif Zip64_Extra then 16#FFFF_FFFF#
            else Interfaces.Unsigned_32 (Plain'Length));
      begin
         Put32 (Bytes, Local_Offset, 16#0403_4B50#);
         Put16 (Bytes, Local_Offset + 6, Flags);
         Put16 (Bytes, Local_Offset + 8, Method);
         Put32_U (Bytes, Local_Offset + 18, Local_Size_Value);
         Put32_U (Bytes, Local_Offset + 22, Local_Uncompressed_Value);
         Put16 (Bytes, Local_Offset + 26, Name'Length);
         Put16 (Bytes, Local_Offset + 28, Effective_Local_Extra);
         Put_Text (Bytes, Local_Offset + 30, Name);
         if Bad_Local_Name then
            Bytes (Bytes'First + Local_Offset + 30) := Zlib.Byte (Character'Pos ('b'));
         end if;
         if Zip64_Extra then
            declare
               Extra_Offset : constant Natural := Local_Offset + 30 + Name'Length + Local_Extra_Length;
            begin
               Put16 (Bytes, Extra_Offset, 16#0001#);
               Put16 (Bytes, Extra_Offset + 2, 16);
               Put64_U
                 (Bytes,
                  Extra_Offset + 4,
                  (if Zip64_Too_Large
                   then Interfaces.Shift_Left (Interfaces.Unsigned_64 (1), 63)
                   else Interfaces.Unsigned_64 (Plain'Length)));
               Put64 (Bytes, Extra_Offset + 12, Payload'Length);
            end;
         end if;
         for Index in Payload'Range loop
            Bytes (Bytes'First + Local_Offset + 30 + Name'Length + Effective_Local_Extra + Index - Payload'First) :=
              Payload (Index);
         end loop;
         if Data_Descriptor then
            declare
               Descriptor_Offset : constant Natural :=
                 30 + Name'Length + Effective_Local_Extra + Payload'Length;
            begin
               if Descriptor_Zip64 and then Descriptor_Signature then
                  Put32 (Bytes, Descriptor_Offset, 16#0807_4B50#);
                  Put32 (Bytes, Descriptor_Offset + 4, (if Bad_Data_Descriptor then 0 else 16#3524_41C2#));
                  Put64 (Bytes, Descriptor_Offset + 8, Payload'Length);
                  Put64 (Bytes, Descriptor_Offset + 16, Plain'Length);
               elsif Descriptor_Zip64 then
                  Put32 (Bytes, Descriptor_Offset, (if Bad_Data_Descriptor then 0 else 16#3524_41C2#));
                  Put64 (Bytes, Descriptor_Offset + 4, Payload'Length);
                  Put64 (Bytes, Descriptor_Offset + 12, Plain'Length);
               elsif Descriptor_Signature then
                  Put32 (Bytes, Descriptor_Offset, 16#0807_4B50#);
                  Put32 (Bytes, Descriptor_Offset + 4, (if Bad_Data_Descriptor then 0 else 16#3524_41C2#));
                  Put32 (Bytes, Descriptor_Offset + 8, Payload'Length);
                  Put32 (Bytes, Descriptor_Offset + 12, Plain'Length);
               else
                  Put32 (Bytes, Descriptor_Offset, (if Bad_Data_Descriptor then 0 else 16#3524_41C2#));
                  Put32 (Bytes, Descriptor_Offset + 4, Payload'Length);
                  Put32 (Bytes, Descriptor_Offset + 8, Plain'Length);
               end if;
            end;
         end if;

         Put32 (Bytes, Central_Offset, 16#0201_4B50#);
         Put16 (Bytes, Central_Offset + 8, Flags);
         Put16 (Bytes, Central_Offset + 10, Method);
         Put32 (Bytes, Central_Offset + 16, (if Bad_CRC then 0 else 16#3524_41C2#));
         if Zip64_Size_Markers or else Zip64_Extra then
            for Offset in 20 .. 27 loop
               Bytes (Bytes'First + Central_Offset + Offset) := 16#FF#;
            end loop;
         else
            Put32 (Bytes, Central_Offset + 20, Payload'Length);
            Put32 (Bytes, Central_Offset + 24, Plain'Length);
         end if;
         Put16 (Bytes, Central_Offset + 28, Name'Length);
         Put16 (Bytes, Central_Offset + 30, Effective_Central_Extra);
         Put16 (Bytes, Central_Offset + 32, Central_Comment_Length);
         Put32 (Bytes, Central_Offset + 42, Local_Offset);
         Put_Text (Bytes, Central_Offset + 46, Name);
         if Unicode_Path_Extra then
            declare
               Extra_Offset : constant Natural := Central_Offset + 46 + Name'Length;
            begin
               Put16 (Bytes, Extra_Offset, 16#7075#);
               Put16 (Bytes, Extra_Offset + 2, 5 + Unicode_Name'Length);
               Bytes (Bytes'First + Extra_Offset + 4) :=
                 (if Bad_Unicode_Path_Version then 2 else 1);
               Put32_U
                 (Bytes,
                  Extra_Offset + 5,
                  (if Bad_Unicode_Path_CRC then 0 else CRC32_Text (Name)));
               Put_Text (Bytes, Extra_Offset + 9, Unicode_Name);
            end;
         end if;
         if Zip64_Extra then
            declare
               Extra_Offset : constant Natural :=
                 Central_Offset + 46 + Name'Length + Central_Extra_Length
                 + (if Unicode_Path_Extra then 4 + 5 + Unicode_Name'Length else 0);
            begin
               Put16 (Bytes, Extra_Offset, 16#0001#);
               Put16 (Bytes, Extra_Offset + 2, 16);
               Put64_U
                 (Bytes,
                  Extra_Offset + 4,
                  (if Zip64_Too_Large
                   then Interfaces.Shift_Left (Interfaces.Unsigned_64 (1), 63)
                   else Interfaces.Unsigned_64 (Plain'Length)));
               Put64 (Bytes, Extra_Offset + 12, Payload'Length);
            end;
         end if;
         for Index in 1 .. Central_Comment_Length loop
            Bytes (Bytes'First + Central_Offset + 46 + Name'Length
                   + Effective_Central_Extra + Index - 1) :=
              Zlib.Byte (Character'Pos ('c'));
         end loop;

         if Zip64_Locator then
            Put32 (Bytes, Central_Offset + Central_Size, 16#0706_4B50#);
         end if;
         Put32 (Bytes, EOCD_Offset, 16#0605_4B50#);
         Put16 (Bytes, EOCD_Offset + 8, 1);
         Put16 (Bytes, EOCD_Offset + 10, 1);
         Put32 (Bytes, EOCD_Offset + 12, Central_Size);
         Put32 (Bytes, EOCD_Offset + 16, Central_Offset);
         Put16 (Bytes, EOCD_Offset + 20, Archive_Comment_Length);
         for Index in 1 .. Archive_Comment_Length loop
            Bytes (Bytes'First + EOCD_Offset + 22 + Index - 1) :=
              Zlib.Byte (Character'Pos ('z'));
         end loop;
         return Bytes;
      end Build;
   begin
      if Method = 8 then
         declare
            Status : Zlib.Status_Code;
            Deflated : constant Zlib.Byte_Array := Zlib.Deflate_Raw (Plain, Zlib.Fixed, Status);
         begin
            Assert (Status = Zlib.Ok, "test fixture raw deflate succeeds");
            return Build (Deflated);
         end;
      else
         return Build (Plain);
      end if;
   end One_File_Zip;

   function Stored_Zip_With_Payload
     (Payload : Zlib.Byte_Array;
      Method  : Natural := 0)
      return Zlib.Byte_Array
   is
      Name : constant String := "large.bin";

      function Compressed_For_Method return Zlib.Byte_Array is
         Status : Zlib.Status_Code;
      begin
         case Method is
            when 0 =>
               return Payload;
            when 8 =>
               declare
                  Deflated : constant Zlib.Byte_Array :=
                    Zlib.Deflate_Raw (Payload, Zlib.Fixed, Status);
               begin
                  Assert (Status = Zlib.Ok, "large zip fixture raw deflate succeeds");
                  return Deflated;
               end;
            when 12 =>
               declare
                  Bzip2 : constant Zlib.Byte_Array :=
                    Zlib.BZip2_Encoder.Encode (Payload, Status => Status);
               begin
                  Assert (Status = Zlib.Ok, "zip bzip2 fixture payload compression succeeds");
                  return Bzip2;
               end;
            when 14 =>
               declare
                  Input_Path : constant String := "obj/zip-external-lzma-input.bin";
                  ZIP_Method : Interfaces.Unsigned_16 := 0;
                  ZIP_CRC : Interfaces.Unsigned_32 := 0;
                  ZIP_Uncompressed : Interfaces.Unsigned_64 := 0;
               begin
                  Ada.Directories.Create_Path ("obj");
                  Write_Bytes (Input_Path, Payload);
                  declare
                     LZMA : constant Zlib.Byte_Array :=
                       Zlib.Compress_ZIP_External_File
                         (Input_Path,
                          "LZMA",
                          ZIP_Method,
                          ZIP_CRC,
                          ZIP_Uncompressed,
                          Status);
                  begin
                     Assert (Status = Zlib.Ok, "zip lzma fixture payload compression succeeds");
                     Assert (Natural (ZIP_Method) = 14, "zip lzma fixture method id");
                     Assert (Archive.Types.CRC32_Value (ZIP_CRC) = CRC32_Compute (Payload),
                             "zip lzma fixture crc");
                     Assert (ZIP_Uncompressed = Interfaces.Unsigned_64 (Payload'Length),
                             "zip lzma fixture uncompressed size");
                     return LZMA;
                  end;
               end;
            when 20 | 93 =>
               declare
                  Zstd : constant Zlib.Byte_Array :=
                    Zlib.Zstd_Encoder.Encode (Payload, Status);
               begin
                  Assert (Status = Zlib.Ok, "zip zstd fixture payload compression succeeds");
                  return Zstd;
               end;
            when others =>
               Assert (False, "large zip fixture supports stored, deflate, bzip2, lzma, or zstd");
               return Payload;
         end case;
      end Compressed_For_Method;

      Compressed : constant Zlib.Byte_Array := Compressed_For_Method;
      Local_Offset : constant Natural := 0;
      Central_Offset : constant Natural := 30 + Name'Length + Compressed'Length;
      Central_Size : constant Natural := 46 + Name'Length;
      EOCD_Offset : constant Natural := Central_Offset + Central_Size;
      Total : constant Natural := EOCD_Offset + 22;
      Bytes : Zlib.Byte_Array (1 .. Total) := [others => 0];
      CRC   : constant Archive.Types.CRC32_Value := CRC32_Compute (Payload);
   begin
      Put32 (Bytes, Local_Offset, 16#0403_4B50#);
      Put16 (Bytes, Local_Offset + 8, Method);
      Put32_U (Bytes, Local_Offset + 14, Interfaces.Unsigned_32 (CRC));
      Put32 (Bytes, Local_Offset + 18, Compressed'Length);
      Put32 (Bytes, Local_Offset + 22, Payload'Length);
      Put16 (Bytes, Local_Offset + 26, Name'Length);
      Put_Text (Bytes, Local_Offset + 30, Name);
      for Index in Compressed'Range loop
         Bytes (Bytes'First + Local_Offset + 30 + Name'Length + Index - Compressed'First) :=
           Compressed (Index);
      end loop;

      Put32 (Bytes, Central_Offset, 16#0201_4B50#);
      Put16 (Bytes, Central_Offset + 10, Method);
      Put32_U (Bytes, Central_Offset + 16, Interfaces.Unsigned_32 (CRC));
      Put32 (Bytes, Central_Offset + 20, Compressed'Length);
      Put32 (Bytes, Central_Offset + 24, Payload'Length);
      Put16 (Bytes, Central_Offset + 28, Name'Length);
      Put32 (Bytes, Central_Offset + 42, Local_Offset);
      Put_Text (Bytes, Central_Offset + 46, Name);

      Put32 (Bytes, EOCD_Offset, 16#0605_4B50#);
      Put16 (Bytes, EOCD_Offset + 8, 1);
      Put16 (Bytes, EOCD_Offset + 10, 1);
      Put32 (Bytes, EOCD_Offset + 12, Central_Size);
      Put32 (Bytes, EOCD_Offset + 16, Central_Offset);
      return Bytes;
   end Stored_Zip_With_Payload;

   function Directory_Zip return Zlib.Byte_Array is
      Name : constant String := "dir/";
      Central_Offset : constant Natural := 30 + Name'Length;
      Central_Size : constant Natural := 46 + Name'Length;
      EOCD_Offset : constant Natural := Central_Offset + Central_Size;
      Bytes : Zlib.Byte_Array (1 .. EOCD_Offset + 22) := [others => 0];
   begin
      Put32 (Bytes, 0, 16#0403_4B50#);
      Put16 (Bytes, 26, Name'Length);
      Put_Text (Bytes, 30, Name);
      Put32 (Bytes, Central_Offset, 16#0201_4B50#);
      Put16 (Bytes, Central_Offset + 28, Name'Length);
      Put_Text (Bytes, Central_Offset + 46, Name);
      Put32 (Bytes, EOCD_Offset, 16#0605_4B50#);
      Put16 (Bytes, EOCD_Offset + 8, 1);
      Put16 (Bytes, EOCD_Offset + 10, 1);
      Put32 (Bytes, EOCD_Offset + 12, Central_Size);
      Put32 (Bytes, EOCD_Offset + 16, Central_Offset);
      return Bytes;
   end Directory_Zip;

   function Duplicate_Name_Zip return Zlib.Byte_Array is
      First : constant Zlib.Byte_Array := One_File_Zip;
      Name  : constant String := "a.txt";
      Payload_Length : constant Natural := 3;
      Local2_Offset : constant Natural := 30 + Name'Length + Payload_Length;
      Central_Offset : constant Natural := Local2_Offset + 30 + Name'Length + Payload_Length;
      Central_Size : constant Natural := 2 * (46 + Name'Length);
      EOCD_Offset : constant Natural := Central_Offset + Central_Size;
      Bytes : Zlib.Byte_Array (1 .. EOCD_Offset + 22) := [others => 0];

      procedure Put_Local (Offset : Natural; Text : String) is
      begin
         Put32 (Bytes, Offset, 16#0403_4B50#);
         Put32 (Bytes, Offset + 14, 16#3524_41C2#);
         Put32 (Bytes, Offset + 18, Payload_Length);
         Put32 (Bytes, Offset + 22, Payload_Length);
         Put16 (Bytes, Offset + 26, Name'Length);
         Put_Text (Bytes, Offset + 30, Name);
         Put_Text (Bytes, Offset + 30 + Name'Length, Text);
      end Put_Local;

      procedure Put_Central (Offset : Natural; Local : Natural) is
      begin
         Put32 (Bytes, Offset, 16#0201_4B50#);
         Put32 (Bytes, Offset + 16, 16#3524_41C2#);
         Put32 (Bytes, Offset + 20, Payload_Length);
         Put32 (Bytes, Offset + 24, Payload_Length);
         Put16 (Bytes, Offset + 28, Name'Length);
         Put32 (Bytes, Offset + 42, Local);
         Put_Text (Bytes, Offset + 46, Name);
      end Put_Central;
      pragma Unreferenced (First);
   begin
      Put_Local (0, "abc");
      Put_Local (Local2_Offset, "abc");
      Put_Central (Central_Offset, 0);
      Put_Central (Central_Offset + 46 + Name'Length, Local2_Offset);
      Put32 (Bytes, EOCD_Offset, 16#0605_4B50#);
      Put16 (Bytes, EOCD_Offset + 8, 2);
      Put16 (Bytes, EOCD_Offset + 10, 2);
      Put32 (Bytes, EOCD_Offset + 12, Central_Size);
      Put32 (Bytes, EOCD_Offset + 16, Central_Offset);
      return Bytes;
   end Duplicate_Name_Zip;

   procedure Test_Zip_Index (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
   begin
      declare
         Parsed : constant Archive.Archives.Readers.Zip.Zip_Index_Result :=
           Index_Zip (Empty_Zip);
      begin
         Assert (Parsed.Status = Archive.Archives.Errors.Ok, "empty zip parses");
         Assert (Natural (Parsed.Entries.Length) = 0, "empty zip has no entries");
      end;

      declare
         Parsed : constant Archive.Archives.Readers.Zip.Zip_Index_Result :=
           Index_Zip (One_File_Zip);
         Item : constant Archive.Archives.Entries.Archive_Entry := Parsed.Entries.Element (1);
      begin
         Assert (Parsed.Status = Archive.Archives.Errors.Ok, "stored zip parses");
         Assert (Natural (Parsed.Entries.Length) = 1, "stored zip has one entry");
         Assert (To_String (Item.Original_Path) = "a.txt", "zip original path retained");
         Assert (Item.Kind = Archive.Archives.Entries.Regular_File, "zip file kind mapped");
         Assert (Item.Method = Archive.Archives.Entries.Zip_Stored, "stored method mapped");
         Assert (Item.Encryption = Archive.Archives.Entries.Not_Encrypted, "unencrypted flag mapped");
         Assert (Item.Uncompressed.Present and then Item.Uncompressed.Value = 3, "size retained");
         Assert (Item.Data_Offset.Present, "payload offset retained");
         Assert (Item.CRC32.Present and then Item.CRC32.Value = 16#3524_41C2#, "crc retained");
         Assert
           (Ada.Strings.Fixed.Index (To_String (Item.Format_Metadata), "zip.legacy_name=true") > 0,
            "zip metadata marks bounded legacy filename fallback");

         declare
            Payload : constant Test_Stream_Result :=
              Stream_Zip_Payload (One_File_Zip, Item);
         begin
            Assert (Payload.Status = Archive.Archives.Errors.Ok, "stored payload reads");
            Assert (Payload.Integrity = Archive.Archives.Entries.Verified, "stored payload crc verified");
            Assert (Payload.Bytes_Written = 3, "payload length retained");
            Assert
              (Bytes_Of (Payload) (1) = Zlib.Byte (Character'Pos ('a'))
               and then Bytes_Of (Payload) (2) = Zlib.Byte (Character'Pos ('b'))
               and then Bytes_Of (Payload) (3) = Zlib.Byte (Character'Pos ('c')),
               "payload bytes retained");
         end;
      end;

      declare
         Path : constant String := "obj/zip-stream-payload.zip";
         Deflate_Path : constant String := "obj/zip-stream-deflate-payload.zip";
         Bzip2_Path : constant String := "obj/zip-stream-bzip2-payload.zip";
         Zstd_Path : constant String := "obj/zip-stream-zstd-payload.zip";
         Plain : Zlib.Byte_Array (1 .. 70_000);
         Chunk_Count : Natural := 0;
         Byte_Count  : Natural := 0;
         CRC : Archive.Verification.CRC32.CRC32_State := Archive.Verification.CRC32.Initial;
         Deflate_Chunks : Natural := 0;
         Deflate_Bytes  : Natural := 0;
         Deflate_CRC : Archive.Verification.CRC32.CRC32_State := Archive.Verification.CRC32.Initial;
         Bzip2_Bytes : Natural := 0;
         Bzip2_CRC : Archive.Verification.CRC32.CRC32_State := Archive.Verification.CRC32.Initial;
         LZMA_Bytes : Natural := 0;
         LZMA_CRC : Archive.Verification.CRC32.CRC32_State := Archive.Verification.CRC32.Initial;
         Zstd_Bytes : Natural := 0;
         Zstd_CRC : Archive.Verification.CRC32.CRC32_State := Archive.Verification.CRC32.Initial;

         procedure Consume
           (Bytes : Zlib.Byte_Array;
            Continue : in out Boolean) is
         begin
            Chunk_Count := Chunk_Count + 1;
            Byte_Count := Byte_Count + Bytes'Length;
            Archive.Verification.CRC32.Update (CRC, Bytes);
            Continue := True;
         end Consume;

         procedure Consume_Deflate
           (Bytes : Zlib.Byte_Array;
            Continue : in out Boolean) is
         begin
            Deflate_Chunks := Deflate_Chunks + 1;
            Deflate_Bytes := Deflate_Bytes + Bytes'Length;
            Archive.Verification.CRC32.Update (Deflate_CRC, Bytes);
            Continue := True;
         end Consume_Deflate;

         procedure Consume_Bzip2
           (Bytes : Zlib.Byte_Array;
            Continue : in out Boolean) is
         begin
            Bzip2_Bytes := Bzip2_Bytes + Bytes'Length;
            Archive.Verification.CRC32.Update (Bzip2_CRC, Bytes);
            Continue := True;
         end Consume_Bzip2;

         procedure Consume_LZMA
           (Bytes : Zlib.Byte_Array;
            Continue : in out Boolean) is
         begin
            LZMA_Bytes := LZMA_Bytes + Bytes'Length;
            Archive.Verification.CRC32.Update (LZMA_CRC, Bytes);
            Continue := True;
         end Consume_LZMA;

         procedure Consume_Zstd
           (Bytes : Zlib.Byte_Array;
            Continue : in out Boolean) is
         begin
            Zstd_Bytes := Zstd_Bytes + Bytes'Length;
            Archive.Verification.CRC32.Update (Zstd_CRC, Bytes);
            Continue := True;
         end Consume_Zstd;
      begin
         for Index in Plain'Range loop
            Plain (Index) := Zlib.Byte (Index mod 251);
         end loop;

         Write_Bytes (Path, Stored_Zip_With_Payload (Plain));
         Write_Bytes (Deflate_Path, Stored_Zip_With_Payload (Plain, Method => 8));
         Write_Bytes (Bzip2_Path, Stored_Zip_With_Payload (Plain, Method => 12));
         Write_Bytes ("obj/zip-stream-lzma-payload.zip",
                      Stored_Zip_With_Payload (Plain, Method => 14));
         Write_Bytes (Zstd_Path, Stored_Zip_With_Payload (Plain, Method => 20));

         declare
            Parsed : constant Archive.Archives.Readers.Zip.Zip_Index_Result :=
              Index_Zip (Read_All_Bytes (Path));
            Streamed : constant Archive.Archives.Readers.Zip.Stream_Result :=
              Archive.Archives.Readers.Zip.Stream_Payload_File
                (Path, Parsed.Entries.Element (1), Consume'Access);
         begin
            Assert (Parsed.Status = Archive.Archives.Errors.Ok, "large stored zip parses");
            Assert (Streamed.Status = Archive.Archives.Errors.Ok, "large stored zip streams");
            Assert (Streamed.Integrity = Archive.Archives.Entries.Verified,
                    "large stored zip stream verifies crc");
            Assert (Chunk_Count > 1, "large stored zip emits multiple chunks");
            Assert (Byte_Count = Plain'Length, "large stored zip stream byte count matches payload");
            Assert (Archive.Verification.CRC32.Final (CRC) = CRC32_Compute (Plain),
                    "large stored zip stream bytes match expected crc");
         end;

         declare
            Parsed : constant Archive.Archives.Readers.Zip.Zip_Index_Result :=
              Index_Zip (Read_All_Bytes (Deflate_Path));
            Streamed : constant Archive.Archives.Readers.Zip.Stream_Result :=
              Archive.Archives.Readers.Zip.Stream_Payload_File
                (Deflate_Path, Parsed.Entries.Element (1), Consume_Deflate'Access);
         begin
            Assert (Parsed.Status = Archive.Archives.Errors.Ok, "large deflated zip parses");
            Assert (Parsed.Entries.Element (1).Method = Archive.Archives.Entries.Zip_Deflate,
                    "large deflated zip retains method");
            Assert (Streamed.Status = Archive.Archives.Errors.Ok, "large deflated zip streams");
            Assert (Streamed.Integrity = Archive.Archives.Entries.Verified,
                    "large deflated zip stream verifies crc");
            Assert (Deflate_Chunks > 1, "large deflated zip emits multiple decompressed chunks");
            Assert (Deflate_Bytes = Plain'Length, "large deflated zip stream byte count matches payload");
            Assert
              (Archive.Verification.CRC32.Final (Deflate_CRC) =
                 CRC32_Compute (Plain),
               "large deflated zip stream bytes match expected crc");
         end;

         declare
            Parsed : constant Archive.Archives.Readers.Zip.Zip_Index_Result :=
              Index_Zip (Read_All_Bytes (Bzip2_Path));
            Streamed : constant Archive.Archives.Readers.Zip.Stream_Result :=
              Archive.Archives.Readers.Zip.Stream_Payload_File
                (Bzip2_Path, Parsed.Entries.Element (1), Consume_Bzip2'Access);
         begin
            Assert (Parsed.Status = Archive.Archives.Errors.Ok, "zip bzip2 method parses");
            Assert
              (Parsed.Entries.Element (1).Method =
                 Archive.Archives.Entries.BZip2_Compression,
               "zip bzip2 method maps to supported compression");
            Assert (Streamed.Status = Archive.Archives.Errors.Ok, "zip bzip2 method streams");
            Assert (Streamed.Integrity = Archive.Archives.Entries.Verified,
                    "zip bzip2 method verifies crc");
            Assert (Bzip2_Bytes = Plain'Length, "zip bzip2 stream byte count matches payload");
            Assert
              (Archive.Verification.CRC32.Final (Bzip2_CRC) = CRC32_Compute (Plain),
               "zip bzip2 stream bytes match expected crc");
         end;

         declare
            LZMA_Path : constant String := "obj/zip-stream-lzma-payload.zip";
            Parsed : constant Archive.Archives.Readers.Zip.Zip_Index_Result :=
              Index_Zip (Read_All_Bytes (LZMA_Path));
            Streamed : constant Archive.Archives.Readers.Zip.Stream_Result :=
              Archive.Archives.Readers.Zip.Stream_Payload_File
                (LZMA_Path, Parsed.Entries.Element (1), Consume_LZMA'Access);
         begin
            Assert (Parsed.Status = Archive.Archives.Errors.Ok, "zip lzma method parses");
            Assert
              (Parsed.Entries.Element (1).Method =
                 Archive.Archives.Entries.LZMA_Compression,
               "zip lzma method maps to supported compression");
            Assert (Streamed.Status = Archive.Archives.Errors.Ok, "zip lzma method streams");
            Assert (Streamed.Integrity = Archive.Archives.Entries.Verified,
                    "zip lzma method verifies crc");
            Assert (LZMA_Bytes = Plain'Length, "zip lzma stream byte count matches payload");
            Assert
              (Archive.Verification.CRC32.Final (LZMA_CRC) = CRC32_Compute (Plain),
               "zip lzma stream bytes match expected crc");
         end;

         declare
            Parsed : constant Archive.Archives.Readers.Zip.Zip_Index_Result :=
              Index_Zip (Read_All_Bytes (Zstd_Path));
            Streamed : constant Archive.Archives.Readers.Zip.Stream_Result :=
              Archive.Archives.Readers.Zip.Stream_Payload_File
                (Zstd_Path, Parsed.Entries.Element (1), Consume_Zstd'Access);
         begin
            Assert (Parsed.Status = Archive.Archives.Errors.Ok, "zip zstd method parses");
            Assert
              (Parsed.Entries.Element (1).Method =
                 Archive.Archives.Entries.Zstd_Compression,
               "zip zstd method maps to supported compression");
            Assert (Streamed.Status = Archive.Archives.Errors.Ok, "zip zstd method streams");
            Assert (Streamed.Integrity = Archive.Archives.Entries.Verified,
                    "zip zstd method verifies crc");
            Assert (Zstd_Bytes = Plain'Length, "zip zstd stream byte count matches payload");
            Assert
              (Archive.Verification.CRC32.Final (Zstd_CRC) = CRC32_Compute (Plain),
               "zip zstd stream bytes match expected crc");
         end;
      end;

      declare
         Parsed : constant Archive.Archives.Readers.Zip.Zip_Index_Result :=
           Index_Zip (One_File_Zip (Method => 99, Encrypted => True));
         Item : constant Archive.Archives.Entries.Archive_Entry := Parsed.Entries.Element (1);
         Payload : constant Test_Stream_Result :=
           Stream_Zip_Payload
             (One_File_Zip (Method => 99, Encrypted => True), Item);
      begin
         Assert (Parsed.Status = Archive.Archives.Errors.Ok, "unsupported zip method remains inspectable");
         Assert
           (Item.Method = Archive.Archives.Entries.Unsupported_Compression,
            "unsupported method is explicit");
         Assert (Item.Encryption = Archive.Archives.Entries.Encrypted, "encrypted flag retained");
         Assert (Payload.Status = Archive.Archives.Errors.Unsupported_Method,
                 "encrypted unsupported zip entry cannot publish payload");
         Assert (Payload.Integrity = Archive.Archives.Entries.Not_Available,
                 "encrypted unsupported zip entry has unavailable integrity");
      end;

      declare
         Bytes : constant Zlib.Byte_Array := One_File_Zip (Method => 8);
         Parsed : constant Archive.Archives.Readers.Zip.Zip_Index_Result :=
           Index_Zip (Bytes);
         Item : constant Archive.Archives.Entries.Archive_Entry := Parsed.Entries.Element (1);
         Payload : constant Test_Stream_Result :=
           Stream_Zip_Payload (Bytes, Item);
      begin
         Assert (Parsed.Status = Archive.Archives.Errors.Ok, "deflated zip parses");
         Assert (Item.Method = Archive.Archives.Entries.Zip_Deflate, "deflate method mapped");
         Assert (Payload.Status = Archive.Archives.Errors.Ok, "deflated payload inflates");
         Assert (Payload.Integrity = Archive.Archives.Entries.Verified, "deflated payload crc verified");
         Assert
           (Payload.Bytes_Written = 3
            and then Bytes_Of (Payload) (1) = Zlib.Byte (Character'Pos ('a'))
            and then Bytes_Of (Payload) (2) = Zlib.Byte (Character'Pos ('b'))
            and then Bytes_Of (Payload) (3) = Zlib.Byte (Character'Pos ('c')),
            "deflated payload bytes retained");
      end;

      declare
         Bytes : constant Zlib.Byte_Array := One_File_Zip (Bad_CRC => True);
         Parsed : constant Archive.Archives.Readers.Zip.Zip_Index_Result :=
           Index_Zip (Bytes);
         Payload : constant Test_Stream_Result :=
           Stream_Zip_Payload (Bytes, Parsed.Entries.Element (1));
      begin
         Assert (Payload.Status = Archive.Archives.Errors.Invalid_Format, "bad crc rejects payload");
         Assert (Payload.Integrity = Archive.Archives.Entries.Failed, "bad crc marks failed integrity");
      end;

      declare
         Parsed : constant Archive.Archives.Readers.Zip.Zip_Index_Result :=
           Index_Zip (One_File_Zip (Bad_Local_Name => True));
      begin
         Assert
           (Parsed.Status = Archive.Archives.Errors.Invalid_Format,
            "central/local name mismatch is rejected");
      end;

      declare
         Parsed : constant Archive.Archives.Readers.Zip.Zip_Index_Result :=
           Index_Zip (One_File_Zip (Bad_Local_Size => True));
      begin
         Assert
           (Parsed.Status = Archive.Archives.Errors.Invalid_Format,
            "central/local size mismatch is rejected");
      end;

      declare
         Bytes : constant Zlib.Byte_Array :=
           One_File_Zip
             (Data_Descriptor => True,
              Local_Extra_Length => 4,
              Central_Comment_Length => 5,
              Archive_Comment_Length => 7);
         Parsed : constant Archive.Archives.Readers.Zip.Zip_Index_Result :=
           Index_Zip (Bytes);
         Item : constant Archive.Archives.Entries.Archive_Entry := Parsed.Entries.Element (1);
         Payload : constant Test_Stream_Result :=
           Stream_Zip_Payload (Bytes, Item);
      begin
         Assert (Parsed.Status = Archive.Archives.Errors.Ok,
                 "zip data descriptor with comments parses");
         Assert (Payload.Status = Archive.Archives.Errors.Ok,
                 "zip data descriptor payload reads from central sizes");
         Assert (Payload.Integrity = Archive.Archives.Entries.Verified,
                 "zip data descriptor payload verifies crc");
         Assert (To_String (Item.Comment) = "ccccc",
                 "zip central-directory entry comment is retained");
         Assert
           (Ada.Strings.Fixed.Index (To_String (Item.Format_Metadata), "zip.extra_len=0") > 0
            and then Ada.Strings.Fixed.Index (To_String (Item.Format_Metadata), "zip.comment_len=5") > 0,
            "zip bounded format metadata records extra and comment lengths");
         Assert
           (Ada.Strings.Fixed.Index
              (To_String (Item.Format_Metadata), "zip.data_descriptor=true") > 0
            and then Ada.Strings.Fixed.Index
              (To_String (Item.Format_Metadata), "zip.method=0") > 0,
            "zip metadata records descriptor and method details");
      end;

      declare
         Bytes : constant Zlib.Byte_Array :=
           One_File_Zip (Unicode_Path_Extra => True);
         Parsed : constant Archive.Archives.Readers.Zip.Zip_Index_Result :=
           Index_Zip (Bytes);
         Item : constant Archive.Archives.Entries.Archive_Entry := Parsed.Entries.Element (1);
      begin
         Assert (Parsed.Status = Archive.Archives.Errors.Ok,
                 "zip unicode path extra field parses");
         Assert (To_String (Item.Original_Path) = "a.txt",
                 "zip unicode path extra does not replace original path bytes");
         Assert (To_String (Item.Display_Name) = "unicode.txt",
                 "zip unicode path extra supplies display name");
         Assert
           (Ada.Strings.Fixed.Index (To_String (Item.Format_Metadata), "zip.unicode_path=true") > 0
            and then Ada.Strings.Fixed.Index (To_String (Item.Format_Metadata), "zip.extra_len=20") > 0,
            "zip metadata records unicode path extra");
      end;

      declare
         Parsed : constant Archive.Archives.Readers.Zip.Zip_Index_Result :=
           Index_Zip
             (One_File_Zip (Unicode_Path_Extra => True, Bad_Unicode_Path_CRC => True));
      begin
         Assert
           (Parsed.Status = Archive.Archives.Errors.Invalid_Format,
            "zip unicode path extra field with mismatched name crc is rejected");
      end;

      declare
         Parsed : constant Archive.Archives.Readers.Zip.Zip_Index_Result :=
           Index_Zip
             (One_File_Zip (Unicode_Path_Extra => True, Bad_Unicode_Path_Version => True));
      begin
         Assert
           (Parsed.Status = Archive.Archives.Errors.Invalid_Format,
            "zip unicode path extra field with unsupported version is rejected");
      end;

      declare
         Parsed : constant Archive.Archives.Readers.Zip.Zip_Index_Result :=
           Index_Zip (One_File_Zip (Central_Extra_Length => 3));
      begin
         Assert
           (Parsed.Status = Archive.Archives.Errors.Invalid_Format,
            "zip malformed central extra field is rejected");
      end;

      declare
         Parsed : constant Archive.Archives.Readers.Zip.Zip_Index_Result :=
           Index_Zip
             (One_File_Zip (Data_Descriptor => True, Bad_Data_Descriptor => True));
      begin
         Assert
           (Parsed.Status = Archive.Archives.Errors.Invalid_Format,
            "bad zip data descriptor is rejected");
      end;

      declare
         Bytes : constant Zlib.Byte_Array :=
           One_File_Zip (Data_Descriptor => True, Descriptor_Signature => False);
         Parsed : constant Archive.Archives.Readers.Zip.Zip_Index_Result :=
           Index_Zip (Bytes);
         Item : constant Archive.Archives.Entries.Archive_Entry := Parsed.Entries.Element (1);
         Payload : constant Test_Stream_Result :=
           Stream_Zip_Payload (Bytes, Item);
      begin
         Assert (Parsed.Status = Archive.Archives.Errors.Ok,
                 "zip data descriptor without signature parses");
         Assert (Payload.Status = Archive.Archives.Errors.Ok,
                 "zip signatureless data descriptor payload reads");
         Assert (Payload.Integrity = Archive.Archives.Entries.Verified,
                 "zip signatureless data descriptor payload verifies crc");
      end;

      declare
         Bytes : constant Zlib.Byte_Array :=
           One_File_Zip
             (Data_Descriptor => True,
              Descriptor_Zip64 => True,
              Zip64_Extra => True);
         Parsed : constant Archive.Archives.Readers.Zip.Zip_Index_Result :=
           Index_Zip (Bytes);
         Item : constant Archive.Archives.Entries.Archive_Entry := Parsed.Entries.Element (1);
         Payload : constant Test_Stream_Result :=
           Stream_Zip_Payload (Bytes, Item);
      begin
         Assert (Parsed.Status = Archive.Archives.Errors.Ok,
                 "zip64 data descriptor parses");
         Assert (Payload.Status = Archive.Archives.Errors.Ok,
                 "zip64 data descriptor payload reads");
         Assert (Payload.Integrity = Archive.Archives.Entries.Verified,
                 "zip64 data descriptor payload verifies crc");
         Assert
           (Ada.Strings.Fixed.Index
              (To_String (Item.Format_Metadata), "zip.zip64=true") > 0
            and then Ada.Strings.Fixed.Index
              (To_String (Item.Format_Metadata), "zip.descriptor_zip64=true") > 0,
            "zip metadata records zip64 descriptor use");
      end;

      declare
         Bytes : constant Zlib.Byte_Array := One_File_Zip (Zip64_Extra => True);
         Parsed : constant Archive.Archives.Readers.Zip.Zip_Index_Result :=
           Index_Zip (Bytes);
         Item : constant Archive.Archives.Entries.Archive_Entry := Parsed.Entries.Element (1);
         Payload : constant Test_Stream_Result :=
           Stream_Zip_Payload (Bytes, Item);
      begin
         Assert (Parsed.Status = Archive.Archives.Errors.Ok,
                 "zip64 per-entry extra sizes parse when bounded to host ranges");
         Assert (Item.Compressed.Present and then Item.Compressed.Value = 3,
                 "zip64 compressed size is projected");
         Assert (Item.Uncompressed.Present and then Item.Uncompressed.Value = 3,
                 "zip64 uncompressed size is projected");
         Assert (Payload.Status = Archive.Archives.Errors.Ok,
                 "zip64 small stored payload reads");
         Assert (Payload.Integrity = Archive.Archives.Entries.Verified,
                 "zip64 small stored payload verifies crc");
      end;

      declare
         Parsed : constant Archive.Archives.Readers.Zip.Zip_Index_Result :=
           Index_Zip
             (One_File_Zip (Zip64_Extra => True, Zip64_Too_Large => True));
      begin
         Assert (Parsed.Status = Archive.Archives.Errors.Invalid_Format,
                 "zip64 extra values outside host range are rejected before indexing");
      end;

      declare
         Parsed : constant Archive.Archives.Readers.Zip.Zip_Index_Result :=
           Index_Zip (Directory_Zip);
         Item : constant Archive.Archives.Entries.Archive_Entry := Parsed.Entries.Element (1);
      begin
         Assert (Parsed.Status = Archive.Archives.Errors.Ok, "explicit directory zip parses");
         Assert (Item.Kind = Archive.Archives.Entries.Directory, "directory entry kind is retained");
         Assert (To_String (Item.Original_Path) = "dir/", "directory original path is retained");
         Assert (Item.Uncompressed.Present and then Item.Uncompressed.Value = 0,
                 "directory zip entry retains zero uncompressed size");
         Assert (Item.Integrity = Archive.Archives.Entries.Not_Available,
                 "directory zip entry integrity is unavailable, not fabricated");
      end;

      declare
         Parsed : constant Archive.Archives.Readers.Zip.Zip_Index_Result :=
           Index_Zip (Duplicate_Name_Zip);
      begin
         Assert (Parsed.Status = Archive.Archives.Errors.Ok, "duplicate-name zip parses");
         Assert (Natural (Parsed.Entries.Length) = 2, "duplicate-name zip preserves both physical entries");
         Assert
           (To_String (Parsed.Entries.Element (1).Original_Path) =
            To_String (Parsed.Entries.Element (2).Original_Path),
            "duplicate-name zip keeps duplicate paths distinct");
      end;

      declare
         Parsed : constant Archive.Archives.Readers.Zip.Zip_Index_Result :=
           Index_Zip (One_File_Zip (Zip64_Size_Markers => True));
      begin
         Assert (Parsed.Status = Archive.Archives.Errors.Invalid_Format,
                 "zip64 size markers without extra fields are rejected");
      end;

      declare
         Parsed : constant Archive.Archives.Readers.Zip.Zip_Index_Result :=
           Index_Zip (One_File_Zip (Zip64_Locator => True));
      begin
         Assert (Parsed.Status = Archive.Archives.Errors.Unsupported_Format,
                 "zip64 EOCD locator is rejected explicitly");
      end;

      declare
         Zip64_EOCD_Markers : Zlib.Byte_Array := One_File_Zip;
         Parsed : Archive.Archives.Readers.Zip.Zip_Index_Result;
         EOCD   : constant Natural := Zip64_EOCD_Markers'Length - 22;
      begin
         Put16 (Zip64_EOCD_Markers, EOCD + 8, 16#FFFF#);
         Put16 (Zip64_EOCD_Markers, EOCD + 10, 16#FFFF#);
         Parsed := Index_Zip (Zip64_EOCD_Markers);
         Assert (Parsed.Status = Archive.Archives.Errors.Unsupported_Format,
                 "zip64 EOCD count markers are rejected explicitly");
      end;

      declare
         Bad_Directory_Bounds : Zlib.Byte_Array := One_File_Zip;
         Parsed : Archive.Archives.Readers.Zip.Zip_Index_Result;
         EOCD   : constant Natural := Bad_Directory_Bounds'Length - 22;
      begin
         Put32 (Bad_Directory_Bounds, EOCD + 12, 47);
         Parsed := Index_Zip (Bad_Directory_Bounds);
         Assert (Parsed.Status = Archive.Archives.Errors.Invalid_Format,
                 "central directory must end exactly at EOCD");
      end;

      declare
         Bad_Local_Method : Zlib.Byte_Array := One_File_Zip;
         Parsed : Archive.Archives.Readers.Zip.Zip_Index_Result;
      begin
         Put16 (Bad_Local_Method, 8, 8);
         Parsed := Index_Zip (Bad_Local_Method);
         Assert (Parsed.Status = Archive.Archives.Errors.Invalid_Format,
                 "central/local method mismatch is rejected");
      end;

      declare
         Bad_Payload_Bounds : Zlib.Byte_Array := One_File_Zip (Data_Descriptor => True);
         Parsed : Archive.Archives.Readers.Zip.Zip_Index_Result;
         Central : constant Natural := 30 + 5 + 3 + 16;
      begin
         Put32 (Bad_Payload_Bounds, Central + 20, 1024);
         Parsed := Index_Zip (Bad_Payload_Bounds);
         Assert (Parsed.Status = Archive.Archives.Errors.Invalid_Format,
                 "zip payload and descriptor cannot overlap central directory");
      end;

      declare
         Parsed : constant Archive.Archives.Readers.Zip.Zip_Index_Result :=
           Index_Zip (One_File_Zip (Central_Extra_Length => 65_535));
      begin
         Assert (Parsed.Status = Archive.Archives.Errors.Limit_Exceeded,
                 "oversized central ZIP metadata is rejected before entry projection");
      end;

      declare
         Parsed : constant Archive.Archives.Readers.Zip.Zip_Index_Result :=
           Index_Zip (One_File_Zip (Local_Extra_Length => 65_535));
      begin
         Assert (Parsed.Status = Archive.Archives.Errors.Limit_Exceeded,
                 "oversized local ZIP metadata is rejected before payload projection");
      end;

      declare
         Multi_Disk : Zlib.Byte_Array := One_File_Zip;
         Parsed     : Archive.Archives.Readers.Zip.Zip_Index_Result;
      begin
         Put16 (Multi_Disk, Multi_Disk'Length - 22 + 4, 1);
         Parsed := Index_Zip (Multi_Disk);
         Assert (Parsed.Status = Archive.Archives.Errors.Unsupported_Format,
                 "multi-disk zip is rejected explicitly");
      end;
   end Test_Zip_Index;

   procedure Test_Gzip_Reader (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      Plain : constant Zlib.Byte_Array :=
        [1 => Zlib.Byte (Character'Pos ('a')),
         2 => Zlib.Byte (Character'Pos ('b')),
         3 => Zlib.Byte (Character'Pos ('c'))];
      Status : Zlib.Status_Code;
      Gz : constant Zlib.Byte_Array := Zlib.GZip (Plain, Zlib.Fixed, Status);

      function With_Optional_Header (Bad_Header_CRC : Boolean := False) return Zlib.Byte_Array is
         Header_No_CRC_Length : constant Natural := 30;
         Header_Length        : constant Natural := 32;
         Body_Length          : constant Natural := Gz'Length - 10;
         Result               : Zlib.Byte_Array (1 .. Header_Length + Body_Length) := [others => 0];
         Header               : Zlib.Byte_Array (1 .. Header_No_CRC_Length);
         Header_CRC           : Archive.Types.CRC32_Value;
         Low                  : Natural;
         High                 : Natural;
      begin
         Result (1) := 16#1F#;
         Result (2) := 16#8B#;
         Result (3) := 16#08#;
         Result (4) := 16#1E#;
         Result (11) := 2;
         Result (13) := Zlib.Byte (Character'Pos ('x'));
         Result (14) := Zlib.Byte (Character'Pos ('y'));

         declare
            Name    : constant String := "header.txt";
            Comment : constant String := "note";
         begin
            for Index in Name'Range loop
               Result (14 + Index) := Zlib.Byte (Character'Pos (Name (Index)));
            end loop;
            for Index in Comment'Range loop
               Result (25 + Index) := Zlib.Byte (Character'Pos (Comment (Index)));
            end loop;
         end;

         for Index in Header'Range loop
            Header (Index) := Result (Index);
         end loop;
         Header_CRC := CRC32_Compute (Header);
         Low := Natural (Header_CRC mod 256);
         High := Natural ((Header_CRC / 256) mod 256);
         Result (31) := Zlib.Byte (Low);
         Result (32) := Zlib.Byte (High);
         if Bad_Header_CRC then
            Result (31) := Result (31) xor 16#FF#;
         end if;

         for Index in 11 .. Gz'Last loop
            Result (Header_Length + Index - 10) := Gz (Index);
         end loop;

         return Result;
      end With_Optional_Header;

      function With_Original_Name (Name : String) return Zlib.Byte_Array is
         Body_Length : constant Natural := Gz'Length - 10;
         Result      : Zlib.Byte_Array (1 .. 10 + Name'Length + 1 + Body_Length) := [others => 0];
      begin
         for Index in 1 .. 10 loop
            Result (Index) := Gz (Index);
         end loop;
         Result (4) := 16#08#;
         for Index in Name'Range loop
            Result (10 + Index - Name'First + 1) := Zlib.Byte (Character'Pos (Name (Index)));
         end loop;
         for Index in 11 .. Gz'Last loop
            Result (10 + Name'Length + 1 + Index - 10) := Gz (Index);
         end loop;
         return Result;
      end With_Original_Name;

      function With_Long_Optional_Field (Name_Field : Boolean) return Zlib.Byte_Array is
         Field_Length : constant Natural := 4_097;
         Body_Length  : constant Natural := Gz'Length - 10;
         Result       : Zlib.Byte_Array
           (1 .. 10 + Field_Length + 1 + Body_Length) := [others => 0];
      begin
         for Index in 1 .. 10 loop
            Result (Index) := Gz (Index);
         end loop;
         Result (4) :=
           (if Name_Field then 16#08# else 16#10#);
         for Index in 11 .. 10 + Field_Length loop
            Result (Index) := Zlib.Byte (Character'Pos ('x'));
         end loop;
         for Index in 11 .. Gz'Last loop
            Result (10 + Field_Length + 1 + Index - 10) := Gz (Index);
         end loop;
         return Result;
      end With_Long_Optional_Field;

      function With_Long_Extra_Field return Zlib.Byte_Array is
         Extra_Length : constant Natural := 4_097;
         Body_Length  : constant Natural := Gz'Length - 10;
         Result       : Zlib.Byte_Array
           (1 .. 12 + Extra_Length + Body_Length) := [others => 0];
      begin
         for Index in 1 .. 10 loop
            Result (Index) := Gz (Index);
         end loop;
         Result (4) := 16#04#;
         Result (11) := Zlib.Byte (Extra_Length mod 256);
         Result (12) := Zlib.Byte (Extra_Length / 256);
         for Index in 13 .. 12 + Extra_Length loop
            Result (Index) := Zlib.Byte (Character'Pos ('x'));
         end loop;
         for Index in 11 .. Gz'Last loop
            Result (12 + Extra_Length + Index - 10) := Gz (Index);
         end loop;
         return Result;
      end With_Long_Extra_Field;
   begin
      Assert (Status = Zlib.Ok, "test fixture gzip succeeds");
      declare
         Parsed : constant Archive.Archives.Readers.Gzip.Gzip_Index_Result :=
           Index_Gzip (Gz, Source_Name => "sample.txt.gz");
         Payload : constant Test_Stream_Result :=
           Stream_Gzip_Payload (Gz, Parsed.Item);
      begin
         Assert (Parsed.Status = Archive.Archives.Errors.Ok, "gzip index succeeds");
         Assert (To_String (Parsed.Item.Original_Path) = "sample.txt",
                 "gzip logical name derived from source");
         Assert (Parsed.Item.Method = Archive.Archives.Entries.GZip_Deflate,
                 "gzip method mapped");
         Assert (Parsed.Item.CRC32.Present and then Parsed.Item.CRC32.Value = 16#3524_41C2#,
                 "gzip trailer crc retained");
         Assert (Payload.Status = Archive.Archives.Errors.Ok, "gzip payload inflates");
         Assert (Payload.Integrity = Archive.Archives.Entries.Verified,
                 "gzip payload is verified by zlib trailer checks");
         Assert
           (Payload.Bytes_Written = 3
            and then Bytes_Of (Payload) (1) = Zlib.Byte (Character'Pos ('a'))
            and then Bytes_Of (Payload) (2) = Zlib.Byte (Character'Pos ('b'))
            and then Bytes_Of (Payload) (3) = Zlib.Byte (Character'Pos ('c')),
            "gzip payload bytes retained");
      end;

      declare
         Root    : constant String := "obj/gzip-file-payload-test";
         Gz_Path : constant String := Root & "/sample.txt.gz";
         Big_Path : constant String := Root & "/large.bin.gz";
      begin
         Ada.Directories.Create_Path (Root);
         if Ada.Directories.Exists (Gz_Path) then
            Ada.Directories.Delete_File (Gz_Path);
         end if;
         Write_Bytes (Gz_Path, Gz);

         declare
            Opened : constant Archive.Archives.Readers.Dispatch.Open_Result :=
              Archive.Archives.Readers.Dispatch.Open_File
                (Gz_Path, Source_Name => "sample.txt.gz");
         begin
            Assert (Opened.Status = Archive.Archives.Errors.Ok,
                    "gzip file-backed open succeeds");
            Assert (Opened.Format = Archive.Archives.Formats.GZip_Format,
                    "gzip file-backed open keeps standalone format");

            declare
               Item : constant Archive.Archives.Entries.Archive_Entry :=
                 Archive.Archives.Index.Entry_For (Opened.Index, 2);
               Payload : constant Test_Stream_Result :=
                 Stream_Dispatch_Payload_File
                   (Gz_Path, "sample.txt.gz", Item);
            begin
               Assert (To_String (Item.Original_Path) = "sample.txt",
                       "gzip file-backed index names logical entry");
               Assert
                 (Payload.Status = Archive.Archives.Errors.Ok
                  and then Payload.Integrity = Archive.Archives.Entries.Verified
                  and then Payload.Bytes_Written = 3
                  and then Bytes_Of (Payload) (1) = Zlib.Byte (Character'Pos ('a'))
                  and then Bytes_Of (Payload) (2) = Zlib.Byte (Character'Pos ('b'))
                  and then Bytes_Of (Payload) (3) = Zlib.Byte (Character'Pos ('c')),
                  "gzip file-backed payload streams through zlib with trailer verification");
            end;
         end;

         declare
            Big : Zlib.Byte_Array (1 .. 70_000);
            Big_Status : Zlib.Status_Code;
         begin
            for Index in Big'Range loop
               Big (Index) := Zlib.Byte (Index mod 251);
            end loop;

            declare
               Big_Gz : constant Zlib.Byte_Array := Zlib.GZip (Big, Zlib.Fixed, Big_Status);
               Parsed : constant Archive.Archives.Readers.Gzip.Gzip_Index_Result :=
                 Index_Gzip (Big_Gz, Source_Name => "large.bin.gz");
               Chunk_Count : Natural := 0;
               Byte_Count : Natural := 0;
               CRC : Archive.Verification.CRC32.CRC32_State := Archive.Verification.CRC32.Initial;

               procedure Consume
                 (Bytes : Zlib.Byte_Array;
                  Continue : in out Boolean) is
               begin
                  Chunk_Count := Chunk_Count + 1;
                  Byte_Count := Byte_Count + Bytes'Length;
                  Archive.Verification.CRC32.Update (CRC, Bytes);
                  Continue := True;
               end Consume;
            begin
               Assert (Big_Status = Zlib.Ok, "large gzip fixture compresses");
               Write_Bytes (Big_Path, Big_Gz);

               declare
                  Streamed : constant Archive.Archives.Readers.Gzip.Stream_Result :=
                    Archive.Archives.Readers.Gzip.Stream_Payload_File
                      (Big_Path, Parsed.Item, Consume'Access);
               begin
                  Assert (Parsed.Status = Archive.Archives.Errors.Ok, "large gzip indexes");
                  Assert (Streamed.Status = Archive.Archives.Errors.Ok, "large gzip streams");
                  Assert (Streamed.Integrity = Archive.Archives.Entries.Verified,
                          "large gzip stream verifies trailer and crc");
                  Assert (Chunk_Count > 1, "large gzip emits multiple decompressed chunks");
                  Assert (Byte_Count = Big'Length, "large gzip stream byte count matches payload");
                  Assert
                    (Archive.Verification.CRC32.Final (CRC) = CRC32_Compute (Big),
                     "large gzip stream bytes match expected crc");
               end;
            end;
         end;
      end;

      declare
         Rich : constant Zlib.Byte_Array := With_Optional_Header;
         Parsed : constant Archive.Archives.Readers.Gzip.Gzip_Index_Result :=
           Index_Gzip (Rich, Source_Name => "ignored.gz");
         Payload : constant Test_Stream_Result :=
           Stream_Gzip_Payload (Rich, Parsed.Item);
      begin
         Assert (Parsed.Status = Archive.Archives.Errors.Ok,
                 "gzip optional header indexes");
         Assert (To_String (Parsed.Item.Original_Path) = "header.txt",
                 "gzip original filename has priority");
         Assert (Parsed.Header.Has_Name and then Parsed.Header.Has_Comment,
                 "gzip header metadata records name and comment");
         Assert (Parsed.Header.Extra_Length = 2 and then Parsed.Header.Has_Header_CRC,
                 "gzip header metadata records extra and header crc");
         Assert (Parsed.Header.Header_Length = 32,
                 "gzip header length includes optional fields");
         Assert (Payload.Status = Archive.Archives.Errors.Ok,
                 "gzip optional header payload inflates");
      end;

      declare
         Unsafe_Name : constant Zlib.Byte_Array := With_Original_Name ("../evil.txt");
         Parsed : constant Archive.Archives.Readers.Gzip.Gzip_Index_Result :=
           Index_Gzip (Unsafe_Name, Source_Name => "safe.txt.gz");
         Payload : constant Test_Stream_Result :=
           Stream_Gzip_Payload (Unsafe_Name, Parsed.Item);
      begin
         Assert (Parsed.Status = Archive.Archives.Errors.Ok,
                 "gzip unsafe original filename still indexes");
         Assert (To_String (Parsed.Item.Original_Path) = "safe.txt",
                 "gzip unsafe original filename falls back to safe source name");
         Assert (Payload.Status = Archive.Archives.Errors.Ok,
                 "gzip unsafe-name fallback payload still inflates");
      end;

      declare
         Unsafe_Name : constant Zlib.Byte_Array := With_Original_Name ("/absolute.txt");
         Parsed : constant Archive.Archives.Readers.Gzip.Gzip_Index_Result :=
           Index_Gzip (Unsafe_Name, Source_Name => "bad/name.gz");
      begin
         Assert (Parsed.Status = Archive.Archives.Errors.Ok,
                 "gzip unsafe source and header still produce deterministic entry");
         Assert (To_String (Parsed.Item.Original_Path) = "gzip-payload",
                 "gzip unsafe names use locale-neutral generated fallback");
      end;

      declare
         Bad_Header : constant Zlib.Byte_Array := With_Optional_Header (Bad_Header_CRC => True);
         Parsed : constant Archive.Archives.Readers.Gzip.Gzip_Index_Result :=
           Index_Gzip (Bad_Header);
      begin
         Assert (Parsed.Status = Archive.Archives.Errors.Invalid_Format,
                 "gzip invalid header crc is rejected during indexing");
      end;

      declare
         Parsed : constant Archive.Archives.Readers.Gzip.Gzip_Index_Result :=
           Index_Gzip (With_Long_Optional_Field (Name_Field => True));
      begin
         Assert (Parsed.Status = Archive.Archives.Errors.Limit_Exceeded,
                 "gzip original filename beyond metadata limit is rejected explicitly");
      end;

      declare
         Parsed : constant Archive.Archives.Readers.Gzip.Gzip_Index_Result :=
           Index_Gzip (With_Long_Extra_Field);
      begin
         Assert (Parsed.Status = Archive.Archives.Errors.Limit_Exceeded,
                 "gzip extra field beyond metadata limit is rejected explicitly");
      end;

      declare
         Parsed : constant Archive.Archives.Readers.Gzip.Gzip_Index_Result :=
           Index_Gzip (With_Long_Optional_Field (Name_Field => False));
      begin
         Assert (Parsed.Status = Archive.Archives.Errors.Limit_Exceeded,
                 "gzip comment beyond metadata limit is rejected explicitly");
      end;

      declare
         Reserved : Zlib.Byte_Array := Gz;
         Parsed   : Archive.Archives.Readers.Gzip.Gzip_Index_Result;
      begin
         Reserved (4) := Reserved (4) or 16#E0#;
         Parsed := Index_Gzip (Reserved);
         Assert (Parsed.Status = Archive.Archives.Errors.Invalid_Format,
                 "gzip reserved header flags are rejected");
      end;

      declare
         Corrupt : Zlib.Byte_Array := Gz;
      begin
         Corrupt (Corrupt'Last - 7) := Corrupt (Corrupt'Last - 7) xor 16#FF#;
         declare
            Payload : constant Test_Stream_Result :=
              Stream_Gzip_Payload
                (Corrupt, Index_Gzip (Corrupt).Item);
         begin
            Assert (Payload.Status = Archive.Archives.Errors.Invalid_Format,
                    "bad gzip trailer rejects payload");
            Assert (Payload.Integrity = Archive.Archives.Entries.Failed,
                    "bad gzip trailer marks integrity failed");
         end;
      end;

      declare
         Truncated : Zlib.Byte_Array (Gz'First .. Gz'Last - 2);
      begin
         for Index in Truncated'Range loop
            Truncated (Index) := Gz (Index);
         end loop;
         declare
            Parsed : constant Archive.Archives.Readers.Gzip.Gzip_Index_Result :=
              Index_Gzip (Truncated, Source_Name => "short.gz");
            Payload : constant Test_Stream_Result :=
              Stream_Gzip_Payload (Truncated, Parsed.Item);
         begin
            Assert (Parsed.Status = Archive.Archives.Errors.Ok,
                    "gzip truncated trailer may still expose bounded metadata");
            Assert (Payload.Status = Archive.Archives.Errors.Invalid_Format,
                    "gzip truncated stream is rejected on payload access");
            Assert (Payload.Integrity = Archive.Archives.Entries.Failed,
                    "gzip truncated stream marks integrity failed");
         end;
      end;
   end Test_Gzip_Reader;

   procedure Test_Zlib_Adapter_Limits (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      Plain : constant Zlib.Byte_Array :=
        [1 => Zlib.Byte (Character'Pos ('a')),
         2 => Zlib.Byte (Character'Pos ('b')),
         3 => Zlib.Byte (Character'Pos ('c'))];
      Status : Zlib.Status_Code;
      Raw    : constant Zlib.Byte_Array := Zlib.Deflate_Raw (Plain, Zlib.Fixed, Status);
      Cancel : aliased Archive.Tasking.Cancellation.Token;
   begin
      Assert (Status = Zlib.Ok, "raw deflate fixture builds");

      declare
         Inflated : constant Test_Zlib_Result :=
           Test_Inflate
             (Raw, Archive.Compression.Zlib.Raw_Deflate);
      begin
         Assert (Inflated.Status = Archive.Archives.Errors.Ok, "adapter inflates raw deflate");
         Assert (Inflated.Stream_Ended, "adapter reports stream end");
         Assert (Inflated.Compressed_Bytes = Archive.Types.Compressed_Size (Raw'Length),
                 "adapter counts compressed bytes");
         Assert (Inflated.Uncompressed_Bytes = 3, "adapter counts output bytes");
         Assert (Byte_Length (Inflated) = 3, "adapter returns output bytes");
      end;

      declare
         Output_Limited_Result : constant Test_Zlib_Result :=
           Test_Inflate
             (Raw,
              Archive.Compression.Zlib.Raw_Deflate,
              Limits => (Max_Output_Bytes => 2, Max_Ratio => 1_000));
      begin
         Assert (Output_Limited_Result.Status = Archive.Archives.Errors.Limit_Exceeded,
                 "adapter enforces output limit");
         Assert (Output_Limited_Result.Output_Limited, "adapter marks output limit");
         Assert (Byte_Length (Output_Limited_Result) = 0, "limited output is not published");
      end;

      declare
         Bulk : constant Zlib.Byte_Array (1 .. 512) := [others => Zlib.Byte (Character'Pos ('a'))];
         Bulk_Status : Zlib.Status_Code;
         Bulk_Raw : constant Zlib.Byte_Array := Zlib.Deflate_Raw (Bulk, Zlib.Fixed, Bulk_Status);
      begin
         Assert (Bulk_Status = Zlib.Ok, "bulk raw deflate fixture builds");

         declare
            Ratio_Limited : constant Test_Zlib_Result :=
              Test_Inflate
                (Bulk_Raw,
                 Archive.Compression.Zlib.Raw_Deflate,
                 Limits => (Max_Output_Bytes => 1024, Max_Ratio => 1));
         begin
            Assert (Ratio_Limited.Status = Archive.Archives.Errors.Limit_Exceeded,
                    "adapter enforces ratio limit");
            Assert (Ratio_Limited.Ratio_Limited, "adapter marks ratio limit");
            Assert (Byte_Length (Ratio_Limited) = 0, "ratio-limited output is not published");
         end;
      end;

      Cancel.Cancel;
      declare
         Cancelled : constant Test_Zlib_Result :=
           Test_Inflate
             (Raw,
              Archive.Compression.Zlib.Raw_Deflate,
              Cancellation => Cancel'Access);
      begin
         Assert (Cancelled.Status = Archive.Archives.Errors.Cancelled,
                 "adapter maps cancellation");
         Assert (Cancelled.Cancelled, "adapter marks cancellation");
         Assert (Byte_Length (Cancelled) = 0, "cancelled output is not published");
      end;

      Cancel.Reset;
      declare
         Deflated : constant Test_Zlib_Result :=
           Test_Deflate
             (Plain, Archive.Compression.Zlib.Raw_Deflate);
         Inflated : constant Test_Zlib_Result :=
           Test_Inflate
             (Bytes_Of (Deflated), Archive.Compression.Zlib.Raw_Deflate);
      begin
         Assert (Deflated.Status = Archive.Archives.Errors.Ok,
                 "adapter builds raw deflate output");
         Assert (Deflated.Input_Bytes = 3, "adapter counts deflate input");
         Assert (Deflated.Output_Bytes = Archive.Types.Compressed_Size (Byte_Length (Deflated)),
                 "adapter counts deflate output");
         Assert (Inflated.Status = Archive.Archives.Errors.Ok
                 and then Byte_Length (Inflated) = 3
                 and then Bytes_Of (Inflated) (1) = Zlib.Byte (Character'Pos ('a')),
                 "adapter raw deflate round-trips");
      end;

      declare
         Gzip : constant Test_Zlib_Result :=
           Test_Deflate
             (Plain, Archive.Compression.Zlib.Gzip_Wrapped);
         Inflated : constant Test_Zlib_Result :=
           Test_Inflate
             (Bytes_Of (Gzip), Archive.Compression.Zlib.Gzip_Wrapped);
      begin
         Assert (Gzip.Status = Archive.Archives.Errors.Ok,
                 "adapter builds gzip output");
         Assert (Inflated.Status = Archive.Archives.Errors.Ok
                 and then Byte_Length (Inflated) = 3
                 and then Bytes_Of (Inflated) (3) = Zlib.Byte (Character'Pos ('c')),
                 "adapter gzip round-trips");
      end;

      declare
         Stream_Deflated : constant Test_Zlib_Result :=
           Test_Deflate_Streaming
             (Plain,
              Archive.Compression.Zlib.Raw_Deflate,
              Input_Chunk_Bytes => 1,
              Output_Chunk_Bytes => 2);
         Stream_Inflated : constant Test_Zlib_Result :=
           Test_Inflate_Streaming
             (Bytes_Of (Stream_Deflated),
              Archive.Compression.Zlib.Raw_Deflate,
              Input_Chunk_Bytes => 1,
              Output_Chunk_Bytes => 1);
      begin
         Assert (Stream_Deflated.Status = Archive.Archives.Errors.Ok,
                 "streaming adapter builds raw deflate output");
         Assert (Stream_Deflated.Input_Bytes = 3,
                 "streaming adapter counts deflate input");
         Assert (Stream_Inflated.Status = Archive.Archives.Errors.Ok,
                 "streaming adapter inflates raw deflate output");
         Assert (Stream_Inflated.Stream_Ended,
                 "streaming adapter reports stream end");
         Assert
           (Stream_Inflated.Compressed_Bytes =
              Archive.Types.Compressed_Size (Byte_Length (Stream_Deflated))
            and then Stream_Inflated.Uncompressed_Bytes = 3,
            "streaming adapter counts input and output bytes");
         Assert
           (Stream_Deflated.Input_Chunks = 3
            and then Stream_Deflated.Output_Chunks > 0
            and then Stream_Inflated.Input_Chunks >= Byte_Length (Stream_Deflated)
            and then Stream_Inflated.Output_Chunks >= 1,
            "streaming adapter exposes chunk accounting");
         Assert
           (Byte_Length (Stream_Inflated) = 3
            and then Bytes_Of (Stream_Inflated) (1) = Zlib.Byte (Character'Pos ('a'))
            and then Bytes_Of (Stream_Inflated) (3) = Zlib.Byte (Character'Pos ('c')),
            "streaming adapter raw deflate round-trips with tiny chunks");
      end;

      declare
         Stream_Gzip : constant Test_Zlib_Result :=
           Test_Deflate_Streaming
             (Plain,
              Archive.Compression.Zlib.Gzip_Wrapped,
              Input_Chunk_Bytes => 1,
              Output_Chunk_Bytes => 3);
         Stream_Inflated : constant Test_Zlib_Result :=
           Test_Inflate_Streaming
             (Bytes_Of (Stream_Gzip),
              Archive.Compression.Zlib.Gzip_Wrapped,
              Input_Chunk_Bytes => 2,
              Output_Chunk_Bytes => 1);
      begin
         Assert (Stream_Gzip.Status = Archive.Archives.Errors.Ok,
                 "streaming adapter builds gzip output");
         Assert (Stream_Inflated.Status = Archive.Archives.Errors.Ok,
                 "streaming adapter inflates gzip output");
         Assert
           (Byte_Length (Stream_Inflated) = 3
            and then Bytes_Of (Stream_Inflated) (2) = Zlib.Byte (Character'Pos ('b')),
            "streaming adapter gzip round-trips with tiny chunks");
      end;

      declare
         With_Trailing : Zlib.Byte_Array (1 .. Raw'Length + 2);
      begin
         for Index in Raw'Range loop
            With_Trailing (Index - Raw'First + 1) := Raw (Index);
         end loop;
         With_Trailing (Raw'Length + 1) := 16#AA#;
         With_Trailing (Raw'Length + 2) := 16#BB#;

         declare
            Inflated : constant Test_Zlib_Result :=
              Test_Inflate_Streaming
                (With_Trailing,
                 Archive.Compression.Zlib.Raw_Deflate,
                 Input_Chunk_Bytes => 1,
                 Output_Chunk_Bytes => 1);
         begin
            Assert (Inflated.Status = Archive.Archives.Errors.Ok,
                    "streaming adapter accepts caller-owned trailing bytes");
            Assert (Inflated.Compressed_Bytes = Archive.Types.Compressed_Size (Raw'Length),
                    "streaming adapter reports consumed compressed bytes");
            Assert (Inflated.Unused_Input_Bytes = 2,
                    "streaming adapter reports unused trailing bytes");
         end;
      end;

      declare
         Wrong_Wrapper : constant Test_Zlib_Result :=
           Test_Inflate_Streaming
             (Raw,
              Archive.Compression.Zlib.Gzip_Wrapped,
              Input_Chunk_Bytes => 1,
              Output_Chunk_Bytes => 1);
      begin
         Assert (Wrong_Wrapper.Status = Archive.Archives.Errors.Invalid_Format,
                 "streaming adapter maps wrong wrapper mode to invalid stream");
         Assert (not Wrong_Wrapper.Stream_Ended,
                 "wrong wrapper mode does not report stream end");
      end;

      declare
         Truncated : Zlib.Byte_Array (Raw'First .. Raw'Last - 1);
      begin
         for Index in Truncated'Range loop
            Truncated (Index) := Raw (Index);
         end loop;
         declare
            Result : constant Test_Zlib_Result :=
              Test_Inflate_Streaming
                (Truncated,
                 Archive.Compression.Zlib.Raw_Deflate,
                 Input_Chunk_Bytes => 1,
                 Output_Chunk_Bytes => 1);
         begin
            Assert (Result.Status = Archive.Archives.Errors.Invalid_Format,
                    "streaming adapter rejects truncated deflate stream");
         end;
      end;

      declare
         Gzip_A : constant Test_Zlib_Result :=
           Test_Deflate
             (Plain, Archive.Compression.Zlib.Gzip_Wrapped);
         Gzip_B : constant Test_Zlib_Result :=
           Test_Deflate
             (Plain, Archive.Compression.Zlib.Gzip_Wrapped);
         Gzip_A_Bytes : constant Zlib.Byte_Array := Bytes_Of (Gzip_A);
         Gzip_B_Bytes : constant Zlib.Byte_Array := Bytes_Of (Gzip_B);
         Combined : Zlib.Byte_Array (1 .. Gzip_A_Bytes'Length + Gzip_B_Bytes'Length);
      begin
         for Index in Gzip_A_Bytes'Range loop
            Combined (Index - Gzip_A_Bytes'First + 1) := Gzip_A_Bytes (Index);
         end loop;
         for Index in Gzip_B_Bytes'Range loop
            Combined (Gzip_A_Bytes'Length + Index - Gzip_B_Bytes'First + 1) :=
              Gzip_B_Bytes (Index);
         end loop;

         declare
            Inflated : constant Test_Zlib_Result :=
              Test_Inflate_Streaming
                (Combined,
                 Archive.Compression.Zlib.Gzip_Wrapped,
                 Input_Chunk_Bytes => 2,
                 Output_Chunk_Bytes => 1);
         begin
            Assert (Inflated.Status = Archive.Archives.Errors.Ok,
                    "streaming adapter inflates concatenated gzip members");
            Assert (Byte_Length (Inflated) = 6
                    and then Bytes_Of (Inflated) (1) = Zlib.Byte (Character'Pos ('a'))
                    and then Bytes_Of (Inflated) (6) = Zlib.Byte (Character'Pos ('c')),
                    "streaming adapter concatenates gzip member payloads");
         end;
      end;

      declare
         Gzip_A : constant Test_Zlib_Result :=
           Test_Deflate
             (Plain, Archive.Compression.Zlib.Gzip_Wrapped);
         Gzip_B : constant Test_Zlib_Result :=
           Test_Deflate
             (Plain, Archive.Compression.Zlib.Gzip_Wrapped);
         Gzip_A_Bytes : constant Zlib.Byte_Array := Bytes_Of (Gzip_A);
         Gzip_B_Bytes : constant Zlib.Byte_Array := Bytes_Of (Gzip_B);
         Stream : Archive.Compression.Zlib.Inflate_Stream;
         First_Input : Zlib.Byte_Array (1 .. Gzip_A_Bytes'Length);
         Second_Input : Zlib.Byte_Array (1 .. Gzip_B_Bytes'Length);
      begin
         for Index in Gzip_A_Bytes'Range loop
            First_Input (Index - Gzip_A_Bytes'First + 1) := Gzip_A_Bytes (Index);
         end loop;
         for Index in Gzip_B_Bytes'Range loop
            Second_Input (Index - Gzip_B_Bytes'First + 1) := Gzip_B_Bytes (Index);
         end loop;

         Archive.Compression.Zlib.Open
           (Stream,
            Archive.Compression.Zlib.Gzip_Wrapped,
            Output_Chunk_Bytes => 1);

         declare
            First : constant Archive.Compression.Zlib.Stream_Step_Result :=
              Archive.Compression.Zlib.Append (Stream, First_Input);
            Second : constant Archive.Compression.Zlib.Stream_Step_Result :=
              Archive.Compression.Zlib.Append (Stream, Second_Input);
            Final : constant Archive.Compression.Zlib.Stream_Step_Result :=
              Archive.Compression.Zlib.Finish (Stream);
            Closed : constant Archive.Compression.Zlib.Stream_Close_Result :=
              Archive.Compression.Zlib.Close (Stream);
            Closed_Again : constant Archive.Compression.Zlib.Stream_Close_Result :=
              Archive.Compression.Zlib.Close (Stream);
         begin
            Assert
              (First.Status = Archive.Archives.Errors.Ok
               and then Second.Status = Archive.Archives.Errors.Ok
               and then Final.Status = Archive.Archives.Errors.Ok,
               "stateful gzip stream accepts split concatenated members");
            Assert
              (First.Output_Bytes + Second.Output_Bytes + Final.Output_Bytes = 6,
               "stateful gzip stream reports concatenated output bytes");
            Assert
              (Closed.Status = Archive.Archives.Errors.Ok
               and then Closed.Close_Status = Archive.Compression.Zlib.Close_Ok
               and then Closed.Stream_Ended,
               "stateful gzip stream closes after explicit finish");
            Assert
              (Closed_Again.Status = Archive.Archives.Errors.Zlib_Failed
               and then Closed_Again.Close_Status =
                 Archive.Compression.Zlib.Close_Already_Closed,
               "stateful gzip stream reports repeated close");
         end;
      end;

      declare
         Stream : Archive.Compression.Zlib.Inflate_Stream;
         With_Trailing : Zlib.Byte_Array (1 .. Raw'Length + 3);
      begin
         for Index in Raw'Range loop
            With_Trailing (Index - Raw'First + 1) := Raw (Index);
         end loop;
         With_Trailing (Raw'Length + 1) := 16#E1#;
         With_Trailing (Raw'Length + 2) := 16#E2#;
         With_Trailing (Raw'Length + 3) := 16#E3#;

         Archive.Compression.Zlib.Open
           (Stream,
            Archive.Compression.Zlib.Raw_Deflate,
            Output_Chunk_Bytes => 1);

         declare
            Step : constant Archive.Compression.Zlib.Stream_Step_Result :=
              Archive.Compression.Zlib.Append (Stream, With_Trailing);
            Closed : constant Archive.Compression.Zlib.Stream_Close_Result :=
              Archive.Compression.Zlib.Close (Stream);
         begin
            Assert
              (Step.Status = Archive.Archives.Errors.Ok
               and then Step.Stream_Ended
               and then Step.Input_Bytes = Raw'Length
               and then With_Trailing'Length - Step.Input_Bytes = 3,
               "stateful inflate preserves caller-owned trailing bytes");
            Assert
              (Closed.Status = Archive.Archives.Errors.Ok
               and then Closed.Close_Status = Archive.Compression.Zlib.Close_Ok,
               "stateful inflate closes completed stream");
         end;
      end;

      declare
         Stream : Archive.Compression.Zlib.Inflate_Stream;
         Truncated : Zlib.Byte_Array (Raw'First .. Raw'Last - 1);
      begin
         for Index in Truncated'Range loop
            Truncated (Index) := Raw (Index);
         end loop;

         Archive.Compression.Zlib.Open
           (Stream,
            Archive.Compression.Zlib.Raw_Deflate,
            Output_Chunk_Bytes => 1);

         declare
            Step : constant Archive.Compression.Zlib.Stream_Step_Result :=
              Archive.Compression.Zlib.Append (Stream, Truncated);
            Closed : constant Archive.Compression.Zlib.Stream_Close_Result :=
              Archive.Compression.Zlib.Close (Stream);
         begin
            Assert (Step.Status = Archive.Archives.Errors.Ok,
                    "stateful inflate may defer truncation until finalization");
            Assert
              (Closed.Status = Archive.Archives.Errors.Invalid_Format
               and then Closed.Close_Status = Archive.Compression.Zlib.Close_Incomplete,
               "stateful inflate close reports incomplete stream");
         end;
      end;

      declare
         Stream : Archive.Compression.Zlib.Deflate_Stream;
      begin
         Archive.Compression.Zlib.Open
           (Stream,
            Archive.Compression.Zlib.Raw_Deflate,
            Output_Chunk_Bytes => 1);

         declare
            Step : constant Archive.Compression.Zlib.Stream_Step_Result :=
              Archive.Compression.Zlib.Append (Stream, Plain);
            Final : constant Archive.Compression.Zlib.Stream_Step_Result :=
              Archive.Compression.Zlib.Finish (Stream);
            Closed : constant Archive.Compression.Zlib.Stream_Close_Result :=
              Archive.Compression.Zlib.Close (Stream);
            Closed_Again : constant Archive.Compression.Zlib.Stream_Close_Result :=
              Archive.Compression.Zlib.Close (Stream);
         begin
            Assert
              (Step.Status = Archive.Archives.Errors.Ok
               and then Step.Input_Bytes = Plain'Length,
               "stateful deflate consumes appended input");
            Assert
              (Final.Status = Archive.Archives.Errors.Ok
               and then Final.Stream_Ended
               and then Final.Output_Bytes > 0,
               "stateful deflate finalizes output explicitly");
            Assert
              (Closed.Status = Archive.Archives.Errors.Ok
               and then Closed.Close_Status = Archive.Compression.Zlib.Close_Ok
               and then Closed.Stream_Ended,
               "stateful deflate closes completed stream");
            Assert
              (Closed_Again.Status = Archive.Archives.Errors.Zlib_Failed
               and then Closed_Again.Close_Status =
                 Archive.Compression.Zlib.Close_Already_Closed,
               "stateful deflate reports repeated close");
         end;
      end;

      declare
         Stream_Limited : constant Test_Zlib_Result :=
           Test_Inflate_Streaming
             (Raw,
              Archive.Compression.Zlib.Raw_Deflate,
              Limits => (Max_Output_Bytes => 2, Max_Ratio => 1_000),
              Input_Chunk_Bytes => 1,
              Output_Chunk_Bytes => 1);
      begin
         Assert (Stream_Limited.Status = Archive.Archives.Errors.Limit_Exceeded,
                 "streaming adapter enforces output limit");
         Assert (Stream_Limited.Output_Limited,
                 "streaming adapter marks output limit");
      end;

      declare
         Too_Small : constant Test_Zlib_Result :=
           Test_Deflate
             (Plain,
              Archive.Compression.Zlib.Raw_Deflate,
              Max_Output_Bytes => 1);
      begin
         Assert (Too_Small.Status = Archive.Archives.Errors.Limit_Exceeded,
                 "adapter enforces deflate output limit");
         Assert (Too_Small.Output_Limited, "adapter marks deflate output limit");
         Assert (Byte_Length (Too_Small) = 0, "oversized compressed output is not published");
      end;

      declare
         Stream_Too_Small : constant Test_Zlib_Result :=
           Test_Deflate_Streaming
             (Plain,
              Archive.Compression.Zlib.Raw_Deflate,
              Max_Output_Bytes => 1,
              Input_Chunk_Bytes => 1,
              Output_Chunk_Bytes => 1);
      begin
         Assert (Stream_Too_Small.Status = Archive.Archives.Errors.Limit_Exceeded,
                 "streaming adapter enforces deflate output limit");
         Assert (Stream_Too_Small.Output_Limited,
                 "streaming adapter marks deflate output limit");
      end;

      Cancel.Cancel;
      declare
         Cancelled_Deflate : constant Test_Zlib_Result :=
           Test_Deflate
             (Plain,
              Archive.Compression.Zlib.Raw_Deflate,
              Cancellation => Cancel'Access);
      begin
         Assert (Cancelled_Deflate.Status = Archive.Archives.Errors.Cancelled,
                 "adapter maps deflate cancellation");
         Assert (Cancelled_Deflate.Cancelled, "adapter marks deflate cancellation");
         Assert (Byte_Length (Cancelled_Deflate) = 0,
                 "cancelled compressed output is not published");
      end;

      declare
         Cancelled_Streaming : constant Test_Zlib_Result :=
           Test_Inflate_Streaming
             (Raw,
              Archive.Compression.Zlib.Raw_Deflate,
              Cancellation => Cancel'Access);
      begin
         Assert (Cancelled_Streaming.Status = Archive.Archives.Errors.Cancelled,
                 "streaming adapter maps cancellation");
         Assert (Cancelled_Streaming.Cancelled,
                 "streaming adapter marks cancellation");
      end;
   end Test_Zlib_Adapter_Limits;

   procedure Test_Reader_Dispatch (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      Plain : constant Zlib.Byte_Array :=
        [1 => Zlib.Byte (Character'Pos ('a')),
         2 => Zlib.Byte (Character'Pos ('b')),
         3 => Zlib.Byte (Character'Pos ('c'))];
      Status : Zlib.Status_Code;
      Gz : constant Zlib.Byte_Array := Zlib.GZip (Plain, Zlib.Fixed, Status);
      Tar_Gz_Status : Zlib.Status_Code;
      Tar_Gz : constant Zlib.Byte_Array := Zlib.GZip (One_File_Tar, Zlib.Fixed, Tar_Gz_Status);
      Seven_Status : Zlib.Status_Code;
      Seven : constant Zlib.Byte_Array :=
        Zlib.Seven_Zip_Stored (Plain, "payload.bin", Seven_Status);
      Bzip2_Status : Zlib.Status_Code;
      Bzip2 : constant Zlib.Byte_Array :=
        Zlib.BZip2_Encoder.Encode (Plain, Status => Bzip2_Status);
      Zstd_Status : Zlib.Status_Code;
      Zstd : constant Zlib.Byte_Array :=
        Zlib.Zstd_Encoder.Encode (Plain, Zstd_Status);
      Tar : constant Zlib.Byte_Array := One_File_Tar;
   begin
      Assert (Status = Zlib.Ok, "dispatch gzip fixture builds");
      Assert (Tar_Gz_Status = Zlib.Ok, "dispatch tar.gz fixture builds");
      Assert (Seven_Status = Zlib.Ok, "dispatch 7z fixture builds");
      Assert (Bzip2_Status = Zlib.Ok, "dispatch bzip2 fixture builds");
      Assert (Zstd_Status = Zlib.Ok, "dispatch zstd fixture builds");

      declare
         Opened : constant Archive.Archives.Readers.Dispatch.Open_Result :=
           Open_Dispatch (One_File_Zip, Source_Name => "sample.zip");
         Item : constant Archive.Archives.Entries.Archive_Entry :=
           Archive.Archives.Index.Entry_For (Opened.Index, 2);
         Payload : constant Test_Stream_Result :=
           Stream_Dispatch_Payload (One_File_Zip, "sample.zip", Item);
      begin
         Assert (Opened.Status = Archive.Archives.Errors.Ok, "zip dispatch succeeds");
         Assert (Opened.Format = Archive.Archives.Formats.Zip_Format, "zip dispatch records format");
         Assert (Archive.Archives.Index.Physical_Count (Opened.Index) = 1,
                 "zip dispatch publishes physical entry");
         Assert
           (Payload.Status = Archive.Archives.Errors.Ok
            and then Payload.Bytes_Written = 3
            and then Bytes_Of (Payload) (1) = Zlib.Byte (Character'Pos ('a')),
            "zip dispatch payload reads");
      end;

      declare
         Opened : constant Archive.Archives.Readers.Dispatch.Open_Result :=
           Open_Dispatch (Gz, Source_Name => "sample.txt.gz");
         Item : constant Archive.Archives.Entries.Archive_Entry :=
           Archive.Archives.Index.Entry_For (Opened.Index, 2);
         Payload : constant Test_Stream_Result :=
           Stream_Dispatch_Payload (Gz, "sample.txt.gz", Item);
      begin
         Assert (Opened.Status = Archive.Archives.Errors.Ok, "gzip dispatch succeeds");
         Assert (Opened.Format = Archive.Archives.Formats.GZip_Format, "gzip dispatch records format");
         Assert (Archive.Archives.Index.Physical_Count (Opened.Index) = 1,
                 "gzip dispatch publishes logical entry");
         Assert
           (Payload.Status = Archive.Archives.Errors.Ok
            and then Payload.Bytes_Written = 3
            and then Bytes_Of (Payload) (2) = Zlib.Byte (Character'Pos ('b')),
            "gzip dispatch payload reads");
      end;

      declare
         Opened : constant Archive.Archives.Readers.Dispatch.Open_Result :=
           Open_Dispatch (Tar, Source_Name => "sample.tar");
         Item : constant Archive.Archives.Entries.Archive_Entry :=
           Archive.Archives.Index.Entry_For (Opened.Index, 3);
         Payload : constant Test_Stream_Result :=
           Stream_Dispatch_Payload (Tar, "sample.tar", Item);
      begin
         Assert (Opened.Status = Archive.Archives.Errors.Ok, "tar dispatch succeeds through tarlib");
         Assert (Opened.Format = Archive.Archives.Formats.Tar_Format, "tar dispatch records format");
         Assert (Archive.Archives.Index.Physical_Count (Opened.Index) = 1,
                 "tar dispatch publishes physical entry");
         Assert (Archive.Archives.Index.Entry_Count (Opened.Index) = 3,
                 "tar dispatch creates synthetic parent directory");
         Assert (Payload.Status = Archive.Archives.Errors.Ok, "tar payload reads through tarlib");
         Assert
           (Payload.Bytes_Written = 2
            and then Bytes_Of (Payload) (1) = Zlib.Byte (Character'Pos ('o'))
            and then Bytes_Of (Payload) (2) = Zlib.Byte (Character'Pos ('k')),
            "tar payload bytes are returned");
      end;

      declare
         Opened : constant Archive.Archives.Readers.Dispatch.Open_Result :=
           Open_Dispatch (Tar_Gz, Source_Name => "sample.tar.gz");
         Item : constant Archive.Archives.Entries.Archive_Entry :=
           Archive.Archives.Index.Entry_For (Opened.Index, 3);
         Payload : constant Test_Stream_Result :=
           Stream_Dispatch_Payload (Tar_Gz, "sample.tar.gz", Item);
      begin
         Assert (Opened.Status = Archive.Archives.Errors.Ok, "tar.gz dispatch succeeds through zlib and tarlib");
         Assert (Opened.Format = Archive.Archives.Formats.Tar_GZip_Format, "tar.gz dispatch records format");
         Assert (Archive.Archives.Index.Physical_Count (Opened.Index) = 1,
                 "tar.gz dispatch publishes physical entry");
         Assert
           (Payload.Status = Archive.Archives.Errors.Ok
            and then Payload.Bytes_Written = 2
            and then Bytes_Of (Payload) (1) = Zlib.Byte (Character'Pos ('o')),
            "tar.gz dispatch payload reads");
      end;

      declare
         Opened : constant Archive.Archives.Readers.Dispatch.Open_Result :=
           Open_Dispatch (Seven, Source_Name => "sample.7z");
         Item : constant Archive.Archives.Entries.Archive_Entry :=
           Archive.Archives.Index.Entry_For (Opened.Index, 2);
         Payload : constant Test_Stream_Result :=
           Stream_Dispatch_Payload (Seven, "sample.7z", Item);
      begin
         Assert (Opened.Status = Archive.Archives.Errors.Ok,
                 "7z dispatch succeeds through zlib native reader");
         Assert (Opened.Format = Archive.Archives.Formats.Seven_Zip_Format,
                 "7z dispatch records format");
         Assert (Archive.Archives.Index.Physical_Count (Opened.Index) = 1,
                 "7z dispatch publishes physical entry");
         Assert
           (Payload.Status = Archive.Archives.Errors.Ok
            and then Payload.Integrity = Archive.Archives.Entries.Verified
            and then Payload.Bytes_Written = 3
            and then Bytes_Of (Payload) (3) = Zlib.Byte (Character'Pos ('c')),
            "7z dispatch payload reads through zlib");
      end;

      declare
         Opened : constant Archive.Archives.Readers.Dispatch.Open_Result :=
           Open_Dispatch (Zstd, Source_Name => "sample.txt.zst");
         Item : constant Archive.Archives.Entries.Archive_Entry :=
           Archive.Archives.Index.Entry_For (Opened.Index, 2);
         Payload : constant Test_Stream_Result :=
           Stream_Dispatch_Payload (Zstd, "sample.txt.zst", Item);
      begin
         Assert (Opened.Status = Archive.Archives.Errors.Ok,
                 "zstd dispatch succeeds through zlib decoder");
         Assert (Opened.Format = Archive.Archives.Formats.Zstd_Format,
                 "zstd dispatch records format");
         Assert (Archive.Archives.Index.Physical_Count (Opened.Index) = 1,
                 "zstd dispatch publishes logical entry");
         Assert
           (Payload.Status = Archive.Archives.Errors.Ok
            and then Payload.Integrity = Archive.Archives.Entries.Verified
            and then Payload.Bytes_Written = 3
            and then Bytes_Of (Payload) (2) = Zlib.Byte (Character'Pos ('b')),
            "zstd dispatch payload reads through zlib");
      end;

      declare
         Opened : constant Archive.Archives.Readers.Dispatch.Open_Result :=
           Open_Dispatch (Bzip2, Source_Name => "sample.txt.bz2");
         Item : constant Archive.Archives.Entries.Archive_Entry :=
           Archive.Archives.Index.Entry_For (Opened.Index, 2);
         Payload : constant Test_Stream_Result :=
           Stream_Dispatch_Payload (Bzip2, "sample.txt.bz2", Item);
      begin
         Assert (Opened.Status = Archive.Archives.Errors.Ok,
                 "bzip2 dispatch succeeds through zlib decoder");
         Assert (Opened.Format = Archive.Archives.Formats.BZip2_Format,
                 "bzip2 dispatch records format");
         Assert (Archive.Archives.Index.Physical_Count (Opened.Index) = 1,
                 "bzip2 dispatch publishes logical entry");
         Assert
           (Payload.Status = Archive.Archives.Errors.Ok
            and then Payload.Integrity = Archive.Archives.Entries.Verified
            and then Payload.Bytes_Written = 3
            and then Bytes_Of (Payload) (2) = Zlib.Byte (Character'Pos ('b')),
            "bzip2 dispatch payload reads through zlib");
      end;
   end Test_Reader_Dispatch;

   procedure Test_CRC32 (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      ABC : constant Zlib.Byte_Array :=
        [1 => Zlib.Byte (Character'Pos ('a')),
         2 => Zlib.Byte (Character'Pos ('b')),
         3 => Zlib.Byte (Character'Pos ('c'))];
      State : Archive.Verification.CRC32.CRC32_State := Archive.Verification.CRC32.Initial;
   begin
      Assert
        (CRC32_Compute (ABC) = 16#3524_41C2#,
         "crc32 standard vector abc");
      Archive.Verification.CRC32.Update (State, ABC (1 .. 1));
      Archive.Verification.CRC32.Update (State, ABC (2 .. 3));
      Assert
        (Archive.Verification.CRC32.Final (State) = CRC32_Compute (ABC),
         "incremental crc32 matches one-shot compute");
   end Test_CRC32;

   procedure Test_Preview (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      Limits : constant Archive.Preview.Preview_Limits :=
        (Max_Input_Bytes => 4, Max_Text_Chars => 3, Max_Hex_Bytes => 2);
      Text : constant Zlib.Byte_Array :=
        [1 => Zlib.Byte (Character'Pos ('h')),
         2 => Zlib.Byte (Character'Pos ('e')),
         3 => Zlib.Byte (Character'Pos ('l')),
         4 => Zlib.Byte (Character'Pos ('l')),
         5 => Zlib.Byte (Character'Pos ('o'))];
      Binary : constant Zlib.Byte_Array := [1 => 0, 2 => 16#AB#, 3 => 16#CD#];
      PNG : constant Zlib.Byte_Array :=
        [1 => 16#89#,
         2 => Zlib.Byte (Character'Pos ('P')),
         3 => Zlib.Byte (Character'Pos ('N')),
         4 => Zlib.Byte (Character'Pos ('G')),
         5 => 16#0D#,
         6 => 16#0A#,
         7 => 16#1A#,
         8 => 16#0A#,
         9 .. 16 => 0,
         17 => 0,
         18 => 0,
         19 => 0,
         20 => 2,
         21 => 0,
         22 => 0,
         23 => 0,
         24 => 3,
         25 => 0];
      Empty : constant Zlib.Byte_Array (1 .. 0) := [];

      function Stream_Preview
        (Bytes : Zlib.Byte_Array)
         return Archive.Preview.Preview_Result
      is
         Accumulator : Archive.Preview.Preview_Accumulator (Limits.Max_Input_Bytes);
         Continue    : Boolean := True;
      begin
         Archive.Preview.Initialize (Accumulator, Limits);
         Archive.Preview.Append (Accumulator, Bytes, Continue);
         return Archive.Preview.Finish (Accumulator);
      end Stream_Preview;

      function Stream_Entry_Preview
        (Item      : Archive.Archives.Entries.Archive_Entry;
         Bytes     : Zlib.Byte_Array;
         Status    : Archive.Archives.Errors.Error_Code := Archive.Archives.Errors.Ok;
         Integrity : Archive.Archives.Entries.Integrity_State :=
           Archive.Archives.Entries.Verified)
         return Archive.Preview.Preview_Result
      is
         Accumulator : Archive.Preview.Preview_Accumulator (Limits.Max_Input_Bytes);
         Continue    : Boolean := True;
      begin
         Archive.Preview.Initialize (Accumulator, Limits);
         Archive.Preview.Append (Accumulator, Bytes, Continue);
         return
           Archive.Preview.Generate_Entry_From_Accumulator
             (Item, Accumulator, Status, Integrity);
      end Stream_Entry_Preview;
   begin
      declare
         Preview : constant Archive.Preview.Preview_Result :=
           Stream_Preview (Text);
      begin
         Assert (Preview.Kind = Archive.Preview.Text_Preview, "text bytes preview as text");
         Assert (To_String (Preview.Text) = "hel", "text preview respects character limit");
         Assert (Preview.Truncated, "text preview reports truncation");
      end;

      declare
         Accumulator : Archive.Preview.Preview_Accumulator (Limits.Max_Input_Bytes);
         Continue : Boolean := True;
      begin
         Archive.Preview.Initialize (Accumulator, Limits);
         Archive.Preview.Append (Accumulator, Text (1 .. 2), Continue);
         Assert (Continue, "stream preview continues before input limit");
         Archive.Preview.Append (Accumulator, Text (3 .. Text'Last), Continue);
         Assert (not Continue, "stream preview stops at input limit");
         declare
            Preview : constant Archive.Preview.Preview_Result :=
              Archive.Preview.Finish (Accumulator);
         begin
            Assert (Preview.Kind = Archive.Preview.Text_Preview,
                    "stream text preview keeps text kind");
            Assert (To_String (Preview.Text) = "hel",
                    "stream text preview respects character limit");
            Assert (Preview.Truncated, "stream text preview reports truncation");
         end;
      end;

      declare
         Preview : constant Archive.Preview.Preview_Result :=
           Stream_Preview (Binary);
      begin
         Assert (Preview.Kind = Archive.Preview.Hex_Preview, "binary bytes preview as hex");
         Assert (To_String (Preview.Text) = "00 AB", "hex preview is deterministic uppercase");
         Assert (Preview.Truncated, "hex preview reports truncation");
      end;

      declare
         Preview : constant Archive.Preview.Preview_Result :=
           Stream_Preview (Empty);
      begin
         Assert (Preview.Kind = Archive.Preview.Empty_Preview, "empty bytes preview as empty");
         Assert (not Preview.Truncated, "empty preview is not truncated");
      end;

      declare
         Image_Limits : constant Archive.Preview.Preview_Limits :=
           (Max_Input_Bytes => 24, Max_Text_Chars => 24, Max_Hex_Bytes => 24);
         Accumulator : Archive.Preview.Preview_Accumulator
           (Image_Limits.Max_Input_Bytes);
         Continue    : Boolean := True;
         Preview     : Archive.Preview.Preview_Result;
      begin
         Archive.Preview.Initialize (Accumulator, Image_Limits);
         Archive.Preview.Append (Accumulator, PNG, Continue);
         Preview := Archive.Preview.Finish (Accumulator);
         Assert (Preview.Kind = Archive.Preview.Image_Preview,
                 "png bytes preview as image metadata");
         Assert
           (Ada.Strings.Fixed.Index (To_String (Preview.Text), "image.kind=png") > 0
            and then Ada.Strings.Fixed.Index (To_String (Preview.Text), "image.width=2") > 0
            and then Ada.Strings.Fixed.Index (To_String (Preview.Text), "image.height=3") > 0,
            "image preview records deterministic dimensions");
         Assert (Preview.Truncated, "image preview reports input truncation");
      end;

      declare
         Directory : Archive.Archives.Entries.Archive_Entry;
         Link      : Archive.Archives.Entries.Archive_Entry;
         Metadata  : Archive.Archives.Entries.Archive_Entry;
      begin
         Directory.Kind := Archive.Archives.Entries.Directory;
         Directory.Original_Path := To_Unbounded_String ("docs/");
         Link.Kind := Archive.Archives.Entries.Symbolic_Link;
         Link.Original_Path := To_Unbounded_String ("latest");
         Link.Link_Target := To_Unbounded_String ("docs/readme.txt");
         Metadata.Kind := Archive.Archives.Entries.Metadata_Record;
         Metadata.Original_Path := To_Unbounded_String ("pax");
         Metadata.Format_Metadata := To_Unbounded_String ("tar.pax_unknown_records=1");

         declare
            Directory_Preview : constant Archive.Preview.Preview_Result :=
              Stream_Entry_Preview (Directory, Empty);
            Link_Preview : constant Archive.Preview.Preview_Result :=
              Stream_Entry_Preview (Link, Empty);
            Metadata_Preview : constant Archive.Preview.Preview_Result :=
              Stream_Entry_Preview (Metadata, Empty);
         begin
            Assert (Directory_Preview.Kind = Archive.Preview.Directory_Preview,
                    "directory entry previews without payload bytes");
            Assert
              (Ada.Strings.Fixed.Index
                 (To_String (Directory_Preview.Text), "entry.kind=directory") > 0,
               "directory preview records entry kind");
            Assert (Link_Preview.Kind = Archive.Preview.Link_Preview,
                    "link entry previews without payload bytes");
            Assert
              (Ada.Strings.Fixed.Index
                 (To_String (Link_Preview.Text), "entry.link_target=docs/readme.txt") > 0,
               "link preview records link target");
            Assert (Metadata_Preview.Kind = Archive.Preview.Metadata_Preview,
                    "metadata entry previews without payload bytes");
            Assert
              (Ada.Strings.Fixed.Index
                 (To_String (Metadata_Preview.Text), "tar.pax_unknown_records=1") > 0,
               "metadata preview records bounded format metadata");
         end;
      end;

      declare
         Item : Archive.Archives.Entries.Archive_Entry;
         Preview : Archive.Preview.Preview_Result;
      begin
         Item.Kind := Archive.Archives.Entries.Regular_File;
         Item.Original_Path := To_Unbounded_String ("bad.txt");
         Preview :=
           Stream_Entry_Preview
             (Item,
              Text,
              Status    => Archive.Archives.Errors.Invalid_Format,
              Integrity => Archive.Archives.Entries.Failed);
         Assert (Preview.Kind = Archive.Preview.Untrusted_Preview,
                 "failed payload preview is marked untrusted");
         Assert (not Preview.Trusted, "failed integrity preview is not trusted");
         Assert
           (Ada.Strings.Fixed.Index
              (To_String (Preview.Text), "preview.trust=failed") > 0,
            "failed preview records stable trust marker");
      end;
   end Test_Preview;

   procedure Test_Preview_Service (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      Limits : constant Archive.Preview.Preview_Limits :=
        (Max_Input_Bytes => 10, Max_Text_Chars => 10, Max_Hex_Bytes => 10);
      Bytes : constant Zlib.Byte_Array :=
        [1 => Zlib.Byte (Character'Pos ('o')),
         2 => Zlib.Byte (Character'Pos ('k'))];
      Current_Event : constant Archive.Tasking.Events.Event :=
        (Kind => Archive.Tasking.Events.Preview_Completed,
         Session_Generation => 5,
         Operation_Generation => 9,
         Progress_Numerator => 0,
         Progress_Denominator => 0);
      Old_Event : constant Archive.Tasking.Events.Event :=
        (Kind => Archive.Tasking.Events.Preview_Completed,
         Session_Generation => 5,
         Operation_Generation => 8,
         Progress_Numerator => 0,
         Progress_Denominator => 0);
   begin
      declare
         Item : Archive.Archives.Entries.Archive_Entry;
         Calls : Natural := 0;

         function Produce
           (Consumer : not null Archive.Preview.Service.Preview_Chunk_Consumer)
            return Archive.Preview.Service.Preview_Stream_Status
         is
            Continue : Boolean := True;
         begin
            Calls := Calls + 1;
            Consumer.all (Bytes (1 .. 1), Continue);
            if Continue then
               Consumer.all (Bytes (2 .. 2), Continue);
            end if;
            return
              (Status => Archive.Archives.Errors.Ok,
               Integrity => Archive.Archives.Entries.Verified);
         end Produce;
      begin
         Item.Kind := Archive.Archives.Entries.Regular_File;

         declare
            Current : constant Archive.Preview.Service.Preview_Service_Result :=
              Archive.Preview.Service.Complete_Streamed_Entry
                (Item, Produce'Unrestricted_Access, Limits,
                 Cancelled => False,
                 Event => Current_Event,
                 Current_Session => 5,
                 Current_Preview => 9);
            Stale : constant Archive.Preview.Service.Preview_Service_Result :=
              Archive.Preview.Service.Complete_Streamed_Entry
                (Item, Produce'Unrestricted_Access, Limits,
                 Cancelled => False,
                 Event => Old_Event,
                 Current_Session => 5,
                 Current_Preview => 9);
            Cancelled_Entry : constant Archive.Preview.Service.Preview_Service_Result :=
              Archive.Preview.Service.Complete_Streamed_Entry
                (Item, Produce'Unrestricted_Access, Limits,
                 Cancelled => True,
                 Event => Current_Event,
                 Current_Session => 5,
                 Current_Preview => 9);
         begin
            Assert (Current.Accepted, "current streamed preview result accepted");
            Assert (Current.Preview.Kind = Archive.Preview.Text_Preview,
                    "streamed preview generates payload preview");
            Assert (To_String (Current.Preview.Text) = "ok",
                    "streamed preview accumulates chunks");
            Assert (not Stale.Accepted, "stale streamed preview result rejected");
            Assert (not Cancelled_Entry.Accepted,
                    "cancelled streamed preview result rejected");
            Assert (Calls = 1,
                    "stale and cancelled streamed preview do not call producer");
         end;
      end;

      declare
         Item : Archive.Archives.Entries.Archive_Entry;
         Chunk1 : constant Zlib.Byte_Array :=
           [1 => Zlib.Byte (Character'Pos ('a')),
            2 => Zlib.Byte (Character'Pos ('b'))];
         Chunk2 : constant Zlib.Byte_Array :=
           [1 => Zlib.Byte (Character'Pos ('c')),
            2 => Zlib.Byte (Character'Pos ('d'))];
         Tight_Limits : constant Archive.Preview.Preview_Limits :=
           (Max_Input_Bytes => 3, Max_Text_Chars => 10, Max_Hex_Bytes => 10);
         Chunks_Offered : Natural := 0;

         function Produce_Limited
           (Consumer : not null Archive.Preview.Service.Preview_Chunk_Consumer)
            return Archive.Preview.Service.Preview_Stream_Status
         is
            Continue : Boolean := True;
         begin
            Chunks_Offered := Chunks_Offered + 1;
            Consumer.all (Chunk1, Continue);
            if Continue then
               Chunks_Offered := Chunks_Offered + 1;
               Consumer.all (Chunk2, Continue);
            end if;
            if Continue then
               Chunks_Offered := Chunks_Offered + 1;
               Consumer.all (Chunk1, Continue);
            end if;
            return
              (Status => Archive.Archives.Errors.Ok,
               Integrity => Archive.Archives.Entries.Verified);
         end Produce_Limited;
      begin
         Item.Kind := Archive.Archives.Entries.Regular_File;

         declare
            Limited_Result : constant Archive.Preview.Service.Preview_Service_Result :=
              Archive.Preview.Service.Complete_Streamed_Entry
                (Item, Produce_Limited'Unrestricted_Access, Tight_Limits,
                 Cancelled => False,
                 Event => Current_Event,
                 Current_Session => 5,
                 Current_Preview => 9);
         begin
            Assert (Limited_Result.Accepted, "limited streamed preview is accepted");
            Assert (Limited_Result.Bytes_Received = 3,
                    "streamed preview retains only the configured input limit");
            Assert (Limited_Result.Limit_Reached,
                    "streamed preview reports the input limit boundary");
            Assert (Limited_Result.Preview.Truncated,
                    "streamed preview reports truncation after the limit");
            Assert (To_String (Limited_Result.Preview.Text) = "abc",
                    "streamed preview is generated from retained chunks");
            Assert (Chunks_Offered = 2,
                    "stream producer stops when consumer reports the limit");
         end;
      end;
   end Test_Preview_Service;

   procedure Test_Path_Safety (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      R : Archive.Archives.Paths.Normalization_Result;
   begin
      R := Archive.Archives.Paths.Normalize ("dir/file.txt");
      Assert (R.Safety = Archive.Archives.Entries.Safe_Path, "relative path is safe");
      Assert (Natural (R.Components.Length) = 2, "relative components retained");

      R := Archive.Archives.Paths.Normalize ("../outside");
      Assert (R.Safety = Archive.Archives.Entries.Parent_Traversal, "parent traversal blocked");

      R := Archive.Archives.Paths.Normalize ("C:\outside");
      Assert (R.Safety = Archive.Archives.Entries.Windows_Drive_Path, "windows drive path blocked");

      R := Archive.Archives.Paths.Normalize ("CON");
      Assert (R.Safety = Archive.Archives.Entries.Reserved_Name, "reserved name blocked");

      R := Archive.Archives.Paths.Normalize ("/absolute/path");
      Assert (R.Safety = Archive.Archives.Entries.Absolute_Path, "posix absolute path blocked");

      R := Archive.Archives.Paths.Normalize ("\\server\share\file.txt");
      Assert (R.Safety = Archive.Archives.Entries.Absolute_Path, "rooted windows path blocked");

      R := Archive.Archives.Paths.Normalize ("file.txt:stream");
      Assert (R.Safety = Archive.Archives.Entries.Alternate_Data_Stream, "ads path blocked");

      R := Archive.Archives.Paths.Normalize ("././.");
      Assert (R.Safety = Archive.Archives.Entries.Empty_Path, "dot-only path is empty");

      R := Archive.Archives.Paths.Normalize ("a/../../b");
      Assert (R.Safety = Archive.Archives.Entries.Parent_Traversal, "repeated traversal blocked");

      R := Archive.Archives.Paths.Normalize ("Dir/File.TXT");
      Assert
        (To_String
           (Archive.Extraction.Paths.Platform_Key
              (R.Components, Archive.Extraction.Paths.POSIX_Path_Model)) = "Dir/File.TXT",
         "posix path key preserves case");
      Assert
        (To_String
           (Archive.Extraction.Paths.Platform_Key
              (R.Components, Archive.Extraction.Paths.Windows_Path_Model)) = "dir/file.txt",
         "windows path key folds ASCII case");

      declare
         Composed   : constant String :=
           "Caf" & Character'Val (16#C3#) & Character'Val (16#89#) & ".txt";
         Decomposed : constant String :=
           "Cafe" & Character'Val (16#CC#) & Character'Val (16#81#) & ".txt";
         A          : constant Archive.Archives.Paths.Normalization_Result :=
           Archive.Archives.Paths.Normalize (Composed);
         B          : constant Archive.Archives.Paths.Normalization_Result :=
           Archive.Archives.Paths.Normalize (Decomposed);
      begin
         Assert
           (Archive.Extraction.Paths.Platform_Key
              (A.Components, Archive.Extraction.Paths.MacOS_Path_Model) =
            Archive.Extraction.Paths.Platform_Key
              (B.Components, Archive.Extraction.Paths.MacOS_Path_Model),
            "macos path key catches a bounded accent normalization collision");
      end;

      declare
         Root : constant String := "obj/path-destination-test";
         File_Path : constant String := Root & "/not-a-directory";
         Bytes : constant Zlib.Byte_Array := [1 => Zlib.Byte (1)];
      begin
         if Ada.Directories.Exists (Root) then
            Ada.Directories.Delete_Tree (Root);
         end if;
         Ada.Directories.Create_Path (Root);
         Write_Bytes (File_Path, Bytes);

         Assert
           (Archive.Extraction.Paths.Validate_Destination_Root ("") =
              Archive.Extraction.Paths.Destination_Blocked_Empty,
            "empty extraction destination is rejected");
         Assert
           (Archive.Extraction.Paths.Validate_Destination_Root (File_Path) =
              Archive.Extraction.Paths.Destination_Blocked_Not_Directory,
            "file extraction destination is rejected");
         Assert
           (Archive.Extraction.Paths.Validate_Destination_Root (Root & "/missing/out") =
              Archive.Extraction.Paths.Destination_Blocked_Parent_Missing,
            "destination with missing parent is rejected");
         Assert
           (Archive.Extraction.Paths.Validate_Destination_Root (Root & "/new-output") =
              Archive.Extraction.Paths.Destination_Accepted,
            "destination below existing parent is accepted");
      end;

      declare
         Long_Component : constant String (1 .. 256) := [others => 'a'];
         Item : Archive.Archives.Entries.Archive_Entry;
      begin
         Item.Original_Path := To_Unbounded_String (Long_Component);
         Item.Kind := Archive.Archives.Entries.Regular_File;
         declare
            Planned : constant Archive.Extraction.Paths.Planned_Path :=
              Archive.Extraction.Paths.Plan_Relative_Path (Item);
         begin
            Assert
              (Planned.Decision = Archive.Extraction.Paths.Path_Blocked_Unsafe
               and then Planned.Safety = Archive.Archives.Entries.Too_Long,
               "overlong extraction path component is blocked");
         end;
      end;

      declare
         Deep : Unbounded_String;
      begin
         for Index in 1 .. 130 loop
            if Length (Deep) > 0 then
               Append (Deep, "/");
            end if;
            Append (Deep, "d");
         end loop;

         declare
            Item : Archive.Archives.Entries.Archive_Entry;
         begin
            Item.Original_Path := To_Unbounded_String (To_String (Deep));
            Item.Kind := Archive.Archives.Entries.Regular_File;
            declare
               Planned : constant Archive.Extraction.Paths.Planned_Path :=
                 Archive.Extraction.Paths.Plan_Relative_Path (Item);
            begin
               Assert
                 (Planned.Decision = Archive.Extraction.Paths.Path_Blocked_Unsafe
                  and then Planned.Safety = Archive.Archives.Entries.Too_Long,
                  "excessive extraction path depth is blocked");
            end;
         end;
      end;
   end Test_Path_Safety;

   function Fixture_Entry
     (Path : String;
      Kind : Archive.Archives.Entries.Entry_Kind := Archive.Archives.Entries.Regular_File)
      return Archive.Archives.Entries.Archive_Entry
   is
      Item : Archive.Archives.Entries.Archive_Entry;
   begin
      Item.Original_Path := To_Unbounded_String (Path);
      Item.Kind := Kind;
      Item.Method := Archive.Archives.Entries.Zip_Stored;
      Item.Encryption := Archive.Archives.Entries.Not_Encrypted;
      Item.Integrity := Archive.Archives.Entries.Not_Checked;
      return Item;
   end Fixture_Entry;

   procedure Test_Immutable_Index (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      Physical : Archive.Archives.Entries.Entry_Vectors.Vector;
   begin
      Physical.Append (Fixture_Entry ("dir/a.txt"));
      Physical.Append (Fixture_Entry ("dir/a.txt"));
      Physical.Append (Fixture_Entry ("../outside.txt"));

      declare
         Build : constant Archive.Archives.Index.Build_Result :=
           Archive.Archives.Index.Build (Physical);
         Index : constant Archive.Archives.Index.Archive_Index := Build.Index;
         Root_Children : constant Archive.Types.Entry_Id_Vectors.Vector :=
           Archive.Archives.Index.Children (Index, Archive.Archives.Index.Root_Id (Index));
      begin
         Assert (Build.Status = Archive.Archives.Index.Complete, "index build completes");
         Assert (Archive.Archives.Index.Physical_Count (Index) = 3, "physical entries retained");
         Assert (Archive.Archives.Index.Synthetic_Count (Index) = 2, "root and missing parent are synthetic");
         Assert (Archive.Archives.Index.Entry_Count (Index) = 5, "physical plus synthetic count");
         Assert (Natural (Root_Children.Length) = 2, "root has synthetic dir and unsafe leaf");

         declare
            First_File  : constant Archive.Archives.Entries.Archive_Entry :=
              Archive.Archives.Index.Entry_For (Index, 3);
            Second_File : constant Archive.Archives.Entries.Archive_Entry :=
              Archive.Archives.Index.Entry_For (Index, 4);
            Unsafe      : constant Archive.Archives.Entries.Archive_Entry :=
              Archive.Archives.Index.Entry_For (Index, 5);
         begin
            Assert (First_File.Id /= Second_File.Id, "duplicate paths keep distinct ids");
            Assert (To_String (First_File.Original_Path) = To_String (Second_File.Original_Path),
                    "duplicate original paths are preserved");
            Assert (Unsafe.Safety = Archive.Archives.Entries.Parent_Traversal,
                    "unsafe path classification retained");
         end;
      end;

      Physical.Clear;
      Physical.Append (Fixture_Entry ("dir/", Archive.Archives.Entries.Directory));
      Physical.Append (Fixture_Entry ("dir/child.txt"));
      declare
         Build : constant Archive.Archives.Index.Build_Result :=
           Archive.Archives.Index.Build (Physical);
         Index : constant Archive.Archives.Index.Archive_Index := Build.Index;
         Physical_Dir : constant Archive.Archives.Entries.Archive_Entry :=
           Archive.Archives.Index.Entry_For (Index, 2);
         Child : constant Archive.Archives.Entries.Archive_Entry :=
           Archive.Archives.Index.Entry_For (Index, 3);
      begin
         Assert (Build.Status = Archive.Archives.Index.Complete,
                 "explicit directory index build completes");
         Assert (Archive.Archives.Index.Synthetic_Count (Index) = 1,
                 "explicit directory avoids duplicate synthetic parent");
         Assert (Physical_Dir.Kind = Archive.Archives.Entries.Directory,
                 "physical directory record is retained");
         Assert (To_String (Physical_Dir.Display_Name) = "dir",
                 "explicit directory display name uses normalized component");
         Assert (Child.Parent = Physical_Dir.Id,
                 "child entry is parented under physical directory record");
      end;

      Physical.Clear;
      Physical.Append (Fixture_Entry ("a.txt"));
      Physical.Append (Fixture_Entry ("b.txt"));
      declare
         Build : constant Archive.Archives.Index.Build_Result :=
           Archive.Archives.Index.Build_With_Limits
             (Physical, Max_Physical => 1, Max_Synthetic => 1);
      begin
         Assert (Build.Status = Archive.Archives.Index.Failed,
                 "physical entry limit fails before publication");
         Assert (Archive.Archives.Index.Entry_Count (Build.Index) = 0,
                 "failed physical-limit build publishes no index entries");
      end;

      Physical.Clear;
      Physical.Append (Fixture_Entry ("a/b.txt"));
      declare
         Build : constant Archive.Archives.Index.Build_Result :=
           Archive.Archives.Index.Build_With_Limits
             (Physical, Max_Physical => 1, Max_Synthetic => 1);
      begin
         Assert (Build.Status = Archive.Archives.Index.Failed,
                 "synthetic directory limit fails safely");
         Assert (Archive.Archives.Index.Entry_Count (Build.Index) = 0,
                 "failed synthetic-limit build publishes no index entries");
      end;
   end Test_Immutable_Index;

   procedure Test_View_Projection (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      Physical : Archive.Archives.Entries.Entry_Vectors.Vector;
   begin
      Physical.Append (Fixture_Entry ("zeta.txt"));
      Physical.Append (Fixture_Entry ("alpha.txt"));
      Physical.Append (Fixture_Entry ("docs/readme.txt"));

      declare
         Build : constant Archive.Archives.Index.Build_Result :=
           Archive.Archives.Index.Build (Physical);
         Index : constant Archive.Archives.Index.Archive_Index := Build.Index;
         Request : Archive.View_Snapshots.Projection_Request :=
           (Parent            => Archive.Archives.Index.Root_Id (Index),
            Filter_Text       => To_Unbounded_String (""),
            Field             => Archive.View_Snapshots.Sort_By_Name,
            Direction         => Archive.View_Snapshots.Ascending,
            Directories_First => True,
            Limit             => 10);
         Projection : Archive.View_Snapshots.Projection_Result :=
           Archive.View_Snapshots.Project (Index, Request);
      begin
         Assert (Natural (Projection.Entries.Length) = 3, "root projection includes immediate children");
         Assert
           (To_String
              (Archive.Archives.Index.Entry_For
                 (Index, Projection.Entries.Element (1)).Display_Name) = "docs",
            "directories sort first");
         Assert
           (To_String
              (Archive.Archives.Index.Entry_For
                 (Index, Projection.Entries.Element (2)).Display_Name) = "alpha.txt",
            "files then sort by name");

         Request.Filter_Text := To_Unbounded_String ("zeta");
         Projection := Archive.View_Snapshots.Project (Index, Request);
         Assert (Natural (Projection.Entries.Length) = 1, "filter narrows projection");
         Assert (not Projection.Truncated, "untruncated projection reported");

         Request.Filter_Text := To_Unbounded_String ("");
         Request.Limit := 1;
         Projection := Archive.View_Snapshots.Project (Index, Request);
         Assert (Natural (Projection.Entries.Length) = 1, "limit caps projection");
         Assert (Projection.Truncated, "truncated projection reported");
      end;
   end Test_View_Projection;

   procedure Test_Details_Columns (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      Defaults : constant Archive.View_Snapshots.Columns.Column_Vectors.Vector :=
        Archive.View_Snapshots.Columns.Default_Columns;
   begin
      Assert (Archive.View_Snapshots.Columns.Column_Count = 15, "all V1 details columns registered");
      Assert
        (Archive.View_Snapshots.Columns.Token (Archive.View_Snapshots.Columns.Name_Column) = "name",
         "name column has stable token");
      Assert
        (Archive.View_Snapshots.Columns.Name_Key (Archive.View_Snapshots.Columns.Path_Safety_Column) =
           "column.path_safety",
         "path safety column has message key");
      Assert
        (Archive.View_Snapshots.Columns.Contains ("compression_method"),
         "column registry resolves stable token");
      Assert
        (Archive.View_Snapshots.Columns.Id_For_Token ("archive_position") =
           Archive.View_Snapshots.Columns.Archive_Position_Column,
         "column token maps to id");
      Assert
        (Archive.View_Snapshots.Columns.Is_Sortable (Archive.View_Snapshots.Columns.Archive_Position_Column),
         "archive position column is sortable");
      Assert
        (Archive.View_Snapshots.Columns.Sort_Field_For
           (Archive.View_Snapshots.Columns.Archive_Position_Column) =
         Archive.View_Snapshots.Sort_By_Archive_Order,
         "archive position maps to archive-order sort");
      Assert
        (Natural (Defaults.Length) = 7, "default details columns are explicit");
      Assert
        (Archive.Localization.Text
           (Archive.View_Snapshots.Columns.Name_Key (Archive.View_Snapshots.Columns.Name_Column)) =
         "Name",
         "column name key resolves through localization facade");
   end Test_Details_Columns;

   procedure Test_Property_Snapshots (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      Opened : constant Archive.Archives.Readers.Dispatch.Open_Result :=
        Open_Dispatch (One_File_Zip, Source_Name => "sample.zip");
      Parsed : constant Archive.Archives.Readers.Zip.Zip_Index_Result :=
        Index_Zip (One_File_Zip);
      Item   : constant Archive.Archives.Entries.Archive_Entry := Parsed.Entries.Element (1);
      Unsafe : Archive.Archives.Entries.Archive_Entry := Fixture_Entry ("../outside.txt");
      Props  : Archive.View_Snapshots.Entry_Properties.Entry_Property_Snapshot;
   begin
      declare
         Snapshot : constant Archive.View_Snapshots.Archive_Properties.Archive_Property_Snapshot :=
           Archive.View_Snapshots.Archive_Properties.Build
             (Archive.Archives.Formats.Zip_Format, Opened.Index);
      begin
         Assert (Opened.Status = Archive.Archives.Errors.Ok, "property snapshot fixture opens");
         Assert (Snapshot.Format = Archive.Archives.Formats.Zip_Format, "archive snapshot retains format id");
         Assert (To_String (Snapshot.Format_Name_Key) = "format.zip.name", "format name key retained");
         Assert (Snapshot.Entry_Count = 2, "archive snapshot counts root plus physical entry");
         Assert (Snapshot.Physical_Count = 1, "archive snapshot counts physical entries");
         Assert (Snapshot.Synthetic_Count = 1, "archive snapshot counts synthetic root");
         Assert (Snapshot.Can_Verify_Payload, "zip archive snapshot exposes verification capability");
         Assert (Snapshot.Can_Open_Streams, "zip archive snapshot exposes stream capability");
         Assert (Snapshot.Supports_Duplicates, "zip archive snapshot exposes duplicate capability");
      end;

      Props := Archive.View_Snapshots.Entry_Properties.Build (Item);
      Assert (Props.Id = Item.Id, "entry snapshot retains stable id");
      Assert (To_String (Props.Name) = "a.txt", "entry snapshot retains display name");
      Assert (To_String (Props.Original_Path) = "a.txt", "entry snapshot retains original path");
      Assert (Props.Can_Preview, "regular stored entry can preview");
      Assert (Props.Can_Extract, "regular stored entry can extract");
      Assert (Props.Can_Verify, "regular stored entry can verify");
      Assert (Props.Can_Open_Externally, "regular stored entry can open externally");
      Assert (Props.Can_Add and then Props.Can_Replace and then Props.Can_Remove and then Props.Can_Rename,
              "writable entry snapshot exposes write actions");
      Assert (Props.Reason = Archive.Archives.Capabilities.Available,
              "available entry snapshot retains capability reason");
      Assert
        (Props.Preview_Reason = Archive.Archives.Capabilities.Available
         and then Props.Extract_Reason = Archive.Archives.Capabilities.Available
         and then Props.Verify_Reason = Archive.Archives.Capabilities.Available
         and then Props.Replace_Reason = Archive.Archives.Capabilities.Available,
         "available entry snapshot retains per-action capability reasons");
      Assert (To_String (Props.Unavailable_Key) = "", "available entry has no unavailable reason");

      declare
         Caps : constant Archive.Archives.Capabilities.Entry_Capabilities :=
           Archive.Archives.Capabilities.For_Entry (Item, Archive_Writable => False);
      begin
         Assert (Caps.Can_Preview and then Caps.Can_Extract and then Caps.Can_Verify,
                 "read-only archive still allows safe read actions");
         Assert (not Caps.Can_Remove and then not Caps.Can_Rename and then not Caps.Can_Replace,
                 "read-only archive blocks entry mutation actions");
         Assert (Caps.Reason = Archive.Archives.Capabilities.Unsupported_Write_Action,
                 "read-only archive reports stable write-unavailable reason");
         Assert
           (Caps.Preview_Reason = Archive.Archives.Capabilities.Available
            and then Caps.Remove_Reason = Archive.Archives.Capabilities.Unsupported_Write_Action
            and then Caps.Replace_Reason = Archive.Archives.Capabilities.Unsupported_Write_Action
            and then Caps.Rename_Reason = Archive.Archives.Capabilities.Unsupported_Write_Action,
            "read-only archive keeps read reasons distinct from write reasons");
         Assert
           (Archive.Archives.Capabilities.Unavailable_Key (Caps.Reason) =
              "command.unavailable.read_only_archive",
            "read-only write reason maps to stable catalog key");
      end;

      Unsafe.Safety := Archive.Archives.Entries.Parent_Traversal;
      Props := Archive.View_Snapshots.Entry_Properties.Build (Unsafe);
      Assert (not Props.Can_Preview, "unsafe entry preview is unavailable");
      Assert (not Props.Can_Extract, "unsafe entry extraction is unavailable");
      Assert
        (To_String (Props.Unavailable_Key) = "unavailable.unsafe_path",
         "unsafe entry reports stable unavailable reason");
      Assert
        (Props.Extract_Reason = Archive.Archives.Capabilities.Unsafe_Path
         and then Props.Remove_Reason = Archive.Archives.Capabilities.Unsafe_Path
         and then Props.Rename_Reason = Archive.Archives.Capabilities.Unsafe_Path,
         "unsafe entry records path-safety reason for read and write actions");

      Unsafe.Safety := Archive.Archives.Entries.Safe_Path;
      Unsafe.Encryption := Archive.Archives.Entries.Encrypted;
      Props := Archive.View_Snapshots.Entry_Properties.Build (Unsafe);
      Assert (not Props.Can_Preview, "encrypted entry preview is unavailable");
      Assert
        (To_String (Props.Unavailable_Key) = "unavailable.encrypted",
         "encrypted entry reports stable unavailable reason");

      declare
         Link : Archive.Archives.Entries.Archive_Entry :=
           Fixture_Entry ("link", Archive.Archives.Entries.Symbolic_Link);
      begin
         Link.Method := Archive.Archives.Entries.No_Compression;
         Link.Safety := Archive.Archives.Entries.Safe_Path;
         declare
            Caps : constant Archive.Archives.Capabilities.Entry_Capabilities :=
              Archive.Archives.Capabilities.For_Entry (Link);
         begin
            Assert (Caps.Can_Follow_Link, "safe archive link exposes follow capability");
            Assert (not Caps.Can_Extract, "links are not treated as regular extractable files yet");
            Assert
              (Caps.Extract_Reason = Archive.Archives.Capabilities.Unsupported_Entry_Kind
               and then Caps.Follow_Link_Reason = Archive.Archives.Capabilities.Available,
               "link capabilities distinguish extraction from follow-link actions");
         end;
      end;

      declare
         Unsupported : Archive.Archives.Entries.Archive_Entry := Fixture_Entry ("unsupported.bin");
         Caps        : Archive.Archives.Capabilities.Entry_Capabilities;
      begin
         Unsupported.Method := Archive.Archives.Entries.Unsupported_Compression;
         Caps := Archive.Archives.Capabilities.For_Entry (Unsupported);
         Assert (not Caps.Can_Preview and then not Caps.Can_Extract,
                 "unsupported compression blocks read actions");
         Assert (Caps.Reason = Archive.Archives.Capabilities.Unsupported_Method,
                 "unsupported compression reports typed reason");
      end;
   end Test_Property_Snapshots;

   procedure Test_Extraction_Planning (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      Physical : Archive.Archives.Entries.Entry_Vectors.Vector;
   begin
      declare
         Checked : Archive.Archives.Entries.Archive_Entry := Fixture_Entry ("safe/a.txt");
      begin
         Checked.CRC32 := (Present => True, Value => 16#3524_41C2#);
         Physical.Append (Checked);
      end;
      Physical.Append (Fixture_Entry ("safe/a.txt"));
      Physical.Append (Fixture_Entry ("../outside.txt"));
      Physical.Append (Fixture_Entry ("devnode", Archive.Archives.Entries.Character_Device));

      declare
         Build : constant Archive.Archives.Index.Build_Result :=
           Archive.Archives.Index.Build (Physical);
         Index : constant Archive.Archives.Index.Archive_Index := Build.Index;
         Selection : Archive.Types.Entry_Id_Vectors.Vector;
      begin
         Selection.Append (3);
         Selection.Append (4);
         declare
            Plan : constant Archive.Extraction.Plans.Extraction_Plan :=
              Archive.Extraction.Plans.Build (Index, Selection, Session => 7);
         begin
            Assert (Plan.Status = Archive.Extraction.Plans.Plan_Has_Conflicts,
                    "duplicate output path creates conflict");
            Assert (Plan.Conflict_Count = 1, "second duplicate is marked as conflict");
            Assert
              (Plan.Entries.Element (2).Conflict_With = 3,
               "duplicate output conflict records the earlier colliding entry id");
            Assert
              (Plan.Entries.Element (1).Expected_CRC32.Present
               and then Plan.Entries.Element (1).Expected_CRC32.Value = 16#3524_41C2#,
               "extraction plan carries expected payload CRC from immutable entry");
         end;

         Selection.Clear;
         Selection.Append (5);
         declare
            Plan : constant Archive.Extraction.Plans.Extraction_Plan :=
              Archive.Extraction.Plans.Build (Index, Selection, Session => 7);
         begin
            Assert (Plan.Status = Archive.Extraction.Plans.Plan_Blocked,
                    "unsafe traversal blocks plan");
            Assert
              (Plan.Entries.Element (1).Path.Decision = Archive.Extraction.Paths.Path_Blocked_Unsafe,
               "unsafe path has stable block decision");
         end;

         Selection.Clear;
         Selection.Append (6);
         declare
            Plan : constant Archive.Extraction.Plans.Extraction_Plan :=
              Archive.Extraction.Plans.Build (Index, Selection, Session => 7);
         begin
            Assert (Plan.Status = Archive.Extraction.Plans.Plan_Blocked,
                    "unsupported special entry blocks plan");
            Assert
              (Plan.Entries.Element (1).Path.Decision =
                 Archive.Extraction.Paths.Path_Blocked_Unsupported_Entry,
               "special entry has stable block decision");
         end;
      end;

      declare
         Case_Physical : Archive.Archives.Entries.Entry_Vectors.Vector;
      begin
         Case_Physical.Append (Fixture_Entry ("Readme.txt"));
         Case_Physical.Append (Fixture_Entry ("README.TXT"));
         declare
            Build     : constant Archive.Archives.Index.Build_Result :=
              Archive.Archives.Index.Build (Case_Physical);
            Selection : Archive.Types.Entry_Id_Vectors.Vector;
         begin
            Selection.Append (2);
            Selection.Append (3);
            declare
               POSIX_Plan : constant Archive.Extraction.Plans.Extraction_Plan :=
                 Archive.Extraction.Plans.Build
                   (Build.Index, Selection, Session => 8,
                    Platform => Archive.Extraction.Paths.POSIX_Path_Model);
               Windows_Plan : constant Archive.Extraction.Plans.Extraction_Plan :=
                 Archive.Extraction.Plans.Build
                   (Build.Index, Selection, Session => 8,
                    Platform => Archive.Extraction.Paths.Windows_Path_Model);
            begin
               Assert (POSIX_Plan.Status = Archive.Extraction.Plans.Plan_Ready,
                       "posix extraction plan keeps case-distinct output paths");
               Assert
                 (Windows_Plan.Status = Archive.Extraction.Plans.Plan_Has_Conflicts
                  and then Windows_Plan.Conflict_Count = 1,
                  "windows extraction plan catches case-folding collisions");
            end;
         end;
      end;

      declare
         Dir_Physical : Archive.Archives.Entries.Entry_Vectors.Vector;
      begin
         Dir_Physical.Append (Fixture_Entry ("docs/", Archive.Archives.Entries.Directory));
         Dir_Physical.Append (Fixture_Entry ("docs/a.txt"));
         Dir_Physical.Append (Fixture_Entry ("docs/sub/b.txt"));

         declare
            Build     : constant Archive.Archives.Index.Build_Result :=
              Archive.Archives.Index.Build (Dir_Physical);
            Selection : Archive.Types.Entry_Id_Vectors.Vector;
         begin
            Selection.Append (2);
            Selection.Append (3);

            declare
               Plan : constant Archive.Extraction.Plans.Extraction_Plan :=
                 Archive.Extraction.Plans.Build (Build.Index, Selection, Session => 10);
            begin
               Assert (Plan.Requested_Count = 2,
                       "directory extraction plan retains direct selection count");
               Assert (Natural (Plan.Entries.Length) = 4,
                       "directory extraction plan expands selected directory descendants once");
               Assert
                 (Plan.Entries.Element (1).Source = 2
                  and then Plan.Entries.Element (2).Source = 3
                  and then Plan.Entries.Element (3).Source = 4
                  and then Plan.Entries.Element (4).Source = 5,
                  "directory expansion follows stable index child order");
            end;
         end;
      end;
   end Test_Extraction_Planning;

   procedure Test_Extraction_Security_Gate (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      Root : constant String := "obj/extraction-security-gate-test";
      Physical : Archive.Archives.Entries.Entry_Vectors.Vector;
      Payload : constant Zlib.Byte_Array :=
        [1 => Zlib.Byte (Character'Pos ('n')),
         2 => Zlib.Byte (Character'Pos ('e')),
         3 => Zlib.Byte (Character'Pos ('w'))];
      Existing : constant Zlib.Byte_Array :=
        [1 => Zlib.Byte (Character'Pos ('o')),
         2 => Zlib.Byte (Character'Pos ('l')),
         3 => Zlib.Byte (Character'Pos ('d'))];

      function Publish_Test_File
        (Plan      : Archive.Extraction.Plans.Plan_Entry;
         Bytes     : Zlib.Byte_Array;
         Overwrite : Boolean := False;
         Fault     : Archive.Extraction.Execution.Publish_Fault_Point :=
           Archive.Extraction.Execution.No_Publish_Fault)
         return Archive.Extraction.Results.File_Result
      is
         Written : Archive.Resource_Limits.Limit_Value := 0;

         function Provider
           (Source   : Archive.Types.Entry_Id;
            Consumer : not null Archive.Extraction.Execution.Payload_Chunk_Consumer)
            return Archive.Extraction.Execution.Stream_Payload_Result
         is
            pragma Unreferenced (Source);
            Continue : Boolean := True;
         begin
            Consumer.all (Bytes, Continue);
            return
              (Status =>
                 (if Continue
                  then Archive.Extraction.Results.Completed
                  else Archive.Extraction.Results.Cancelled),
               Bytes_Written => Bytes'Length);
         end Provider;
      begin
         return
           Archive.Extraction.Execution.Publish_File_Stream
             (Root, Plan, Provider'Unrestricted_Access, Written,
              Overwrite => Overwrite,
              Fault => Fault);
      end Publish_Test_File;
   begin
      if Ada.Directories.Exists (Root) then
         Ada.Directories.Delete_Tree (Root);
      end if;
      Ada.Directories.Create_Path (Root);

      Physical.Append (Fixture_Entry ("safe/file.txt"));
      Physical.Append (Fixture_Entry ("../escape.txt"));
      Physical.Append (Fixture_Entry ("/absolute.txt"));
      Physical.Append (Fixture_Entry ("C:/drive.txt"));
      Physical.Append (Fixture_Entry ("file.txt:ads"));
      Physical.Append (Fixture_Entry ("CON"));
      Physical.Append (Fixture_Entry ("pipe", Archive.Archives.Entries.FIFO));
      Physical.Append (Fixture_Entry ("link", Archive.Archives.Entries.Symbolic_Link));
      Physical.Append (Fixture_Entry ("hard", Archive.Archives.Entries.Hard_Link));

      declare
         Build : constant Archive.Archives.Index.Build_Result :=
           Archive.Archives.Index.Build (Physical);
         Selection : Archive.Types.Entry_Id_Vectors.Vector;
      begin
         for Id in 4 .. 11 loop
            Selection.Clear;
            Selection.Append (Archive.Types.Entry_Id (Id));
            declare
               Plan : constant Archive.Extraction.Plans.Extraction_Plan :=
                 Archive.Extraction.Plans.Build
                   (Build.Index, Selection, Session => 99,
                    Platform => Archive.Extraction.Paths.Windows_Path_Model);
               Result : constant Archive.Extraction.Results.File_Result :=
                 Publish_Test_File (Plan.Entries.Element (1), Payload);
            begin
               Assert (Plan.Status = Archive.Extraction.Plans.Plan_Blocked,
                       "security gate blocks unsafe or unsupported extraction case");
               Assert (Result.Status = Archive.Extraction.Results.Blocked_By_Plan,
                       "blocked extraction plan cannot publish output");
               Assert (not Ada.Directories.Exists (Root & "/../escape.txt"),
                       "blocked traversal does not create outside output");
            end;
         end loop;

         Selection.Clear;
         Selection.Append (3);
         declare
            Plan : constant Archive.Extraction.Plans.Extraction_Plan :=
              Archive.Extraction.Plans.Build (Build.Index, Selection, Session => 99);
            Initial : constant Archive.Extraction.Results.File_Result :=
              Publish_Test_File (Plan.Entries.Element (1), Existing);
            Blocked : constant Archive.Extraction.Results.File_Result :=
              Publish_Test_File
                (Plan.Entries.Element (1), Payload, Overwrite => False);
            Written : constant Zlib.Byte_Array := Read_All_Bytes (Root & "/safe/file.txt");
         begin
            Assert (Plan.Status = Archive.Extraction.Plans.Plan_Ready,
                    "safe extraction security case is planned");
            Assert (Initial.Status = Archive.Extraction.Results.Completed,
                    "safe extraction publishes initial file");
            Assert (Blocked.Status = Archive.Extraction.Results.Blocked_By_Plan,
                    "existing target blocks extraction without overwrite");
            Assert
              (Written'Length = Existing'Length
               and then Written (1) = Existing (1)
               and then Written (2) = Existing (2)
               and then Written (3) = Existing (3),
               "blocked overwrite preserves previous destination bytes");
         end;

         Selection.Clear;
         Selection.Append (3);
         declare
            Plan : constant Archive.Extraction.Plans.Extraction_Plan :=
              Archive.Extraction.Plans.Build (Build.Index, Selection, Session => 100);
            Initial : constant Archive.Extraction.Results.File_Result :=
              Publish_Test_File
                (Plan.Entries.Element (1), Existing, Overwrite => True);
            Fault_Write : constant Archive.Extraction.Results.File_Result :=
              Publish_Test_File
                (Plan.Entries.Element (1), Payload, Overwrite => True,
                 Fault => Archive.Extraction.Execution.Fault_After_Write);
            After_Write : constant Zlib.Byte_Array := Read_All_Bytes (Root & "/safe/file.txt");
            Fault_Close : constant Archive.Extraction.Results.File_Result :=
              Publish_Test_File
                (Plan.Entries.Element (1), Payload, Overwrite => True,
                 Fault => Archive.Extraction.Execution.Fault_After_Close);
            After_Close : constant Zlib.Byte_Array := Read_All_Bytes (Root & "/safe/file.txt");
            Fault_Rename : constant Archive.Extraction.Results.File_Result :=
              Publish_Test_File
                (Plan.Entries.Element (1), Payload, Overwrite => True,
                 Fault => Archive.Extraction.Execution.Fault_Before_Rename);
            After_Rename : constant Zlib.Byte_Array := Read_All_Bytes (Root & "/safe/file.txt");
            Fault_Race : constant Archive.Extraction.Results.File_Result :=
              Publish_Test_File
                (Plan.Entries.Element (1), Payload, Overwrite => True,
                 Fault => Archive.Extraction.Execution.Fault_Target_Replaced);
            After_Race : constant Zlib.Byte_Array := Read_All_Bytes (Root & "/safe/file.txt");
         begin
            Assert (Initial.Status = Archive.Extraction.Results.Completed,
                    "fault injection fixture creates initial output");
            Assert
              (Fault_Write.Status = Archive.Extraction.Results.Failed_Write
               and then Fault_Close.Status = Archive.Extraction.Results.Failed_Write,
               "write and close faults fail before publication");
            Assert
              (Fault_Rename.Status = Archive.Extraction.Results.Failed_Publish,
               "rename fault reports publish failure");
            Assert
              (Fault_Race.Status = Archive.Extraction.Results.Failed_Containment,
               "target replacement race reports containment failure");
            Assert
              (After_Write'Length = Existing'Length
               and then After_Close'Length = Existing'Length
               and then After_Rename'Length = Existing'Length
               and then After_Race'Length = Existing'Length
               and then After_Write (1) = Existing (1)
               and then After_Close (2) = Existing (2)
               and then After_Rename (3) = Existing (3)
               and then After_Race (1) = Existing (1),
               "publish faults preserve previously published destination bytes");
         end;
      end;
   end Test_Extraction_Security_Gate;

   procedure Test_Write_Planning (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      Physical : Archive.Archives.Entries.Entry_Vectors.Vector;
      Requests : Archive.Writes.Plans.Write_Request_Vectors.Vector;
   begin
      Physical.Append (Fixture_Entry ("safe/a.txt"));
      Physical.Append (Fixture_Entry ("safe/b.txt"));

      declare
         Build : constant Archive.Archives.Index.Build_Result :=
           Archive.Archives.Index.Build (Physical);
         Index : constant Archive.Archives.Index.Archive_Index := Build.Index;
      begin
         Requests.Append
           (Archive.Writes.Plans.Write_Request'
              (Action           => Archive.Writes.Plans.Add_File,
               Source_Entry     => Archive.Types.No_Entry,
               Host_Source      => To_Unbounded_String ("host/new.txt"),
               Target_Path      => To_Unbounded_String ("safe/new.txt"),
               Replacement_Path => Null_Unbounded_String));
         declare
            Plan : constant Archive.Writes.Plans.Write_Plan :=
              Archive.Writes.Plans.Build (Index, Requests, Session => 7);
         begin
            Assert (Plan.Status = Archive.Writes.Plans.Write_Plan_Ready,
                    "safe add request creates ready write plan");
            Assert (Plan.Requested_Count = 1, "write plan retains request count");
         end;

         Requests.Clear;
         Requests.Append
           (Archive.Writes.Plans.Write_Request'
              (Action           => Archive.Writes.Plans.Add_File,
               Source_Entry     => Archive.Types.No_Entry,
               Host_Source      => To_Unbounded_String ("host/outside.txt"),
               Target_Path      => To_Unbounded_String ("../outside.txt"),
               Replacement_Path => Null_Unbounded_String));
         declare
            Plan : constant Archive.Writes.Plans.Write_Plan :=
              Archive.Writes.Plans.Build (Index, Requests, Session => 7);
         begin
            Assert (Plan.Status = Archive.Writes.Plans.Write_Plan_Blocked,
                    "unsafe target blocks archive write plan");
            Assert
              (Plan.Changes.Element (1).Decision =
                 Archive.Writes.Plans.Entry_Blocked_Unsafe_Target,
               "unsafe target reports stable write decision");
         end;

         Requests.Clear;
         Requests.Append
           (Archive.Writes.Plans.Write_Request'
              (Action           => Archive.Writes.Plans.Add_File,
               Source_Entry     => Archive.Types.No_Entry,
               Host_Source      => To_Unbounded_String ("host/dup.txt"),
               Target_Path      => To_Unbounded_String ("safe/a.txt"),
               Replacement_Path => Null_Unbounded_String));
         declare
            Plan : constant Archive.Writes.Plans.Write_Plan :=
              Archive.Writes.Plans.Build (Index, Requests, Session => 7);
         begin
            Assert (Plan.Status = Archive.Writes.Plans.Write_Plan_Has_Conflicts,
                    "existing archive target creates write conflict");
            Assert
              (Plan.Changes.Element (1).Decision =
                 Archive.Writes.Plans.Entry_Conflict_Duplicate_Target,
               "duplicate target reports stable write conflict");
            Assert
              (Plan.Duplicate_Target_Count = 1
               and then Plan.File_Directory_Conflict_Count = 0,
               "duplicate target conflict is counted separately");
         end;

         Requests.Clear;
         Requests.Append
           (Archive.Writes.Plans.Write_Request'
              (Action           => Archive.Writes.Plans.Add_File,
               Source_Entry     => Archive.Types.No_Entry,
               Host_Source      => To_Unbounded_String ("host/nested.txt"),
               Target_Path      => To_Unbounded_String ("safe/new/nested.txt"),
               Replacement_Path => Null_Unbounded_String));
         Requests.Append
           (Archive.Writes.Plans.Write_Request'
              (Action           => Archive.Writes.Plans.Add_File,
               Source_Entry     => Archive.Types.No_Entry,
               Host_Source      => To_Unbounded_String ("host/new.txt"),
               Target_Path      => To_Unbounded_String ("safe/new"),
               Replacement_Path => Null_Unbounded_String));
         declare
            Plan : constant Archive.Writes.Plans.Write_Plan :=
              Archive.Writes.Plans.Build (Index, Requests, Session => 7);
         begin
            Assert (Plan.Status = Archive.Writes.Plans.Write_Plan_Has_Conflicts,
                    "pending file-directory target collision creates write conflict");
            Assert
              (Plan.Changes.Element (2).Decision =
                 Archive.Writes.Plans.Entry_Conflict_File_Directory,
               "file-directory target collision reports stable write conflict");
            Assert
              (Plan.File_Directory_Conflict_Count = 1
               and then Plan.Duplicate_Target_Count = 0,
               "file-directory conflicts are counted separately");
         end;

         Requests.Clear;
         Requests.Append
           (Archive.Writes.Plans.Write_Request'
              (Action           => Archive.Writes.Plans.Remove_Entry,
               Source_Entry     => 99,
               Host_Source      => Null_Unbounded_String,
               Target_Path      => Null_Unbounded_String,
               Replacement_Path => Null_Unbounded_String));
         declare
            Plan : constant Archive.Writes.Plans.Write_Plan :=
              Archive.Writes.Plans.Build (Index, Requests, Session => 7);
         begin
            Assert (Plan.Status = Archive.Writes.Plans.Write_Plan_Blocked,
                    "missing source entry blocks remove plan");
            Assert
              (Plan.Changes.Element (1).Decision =
                 Archive.Writes.Plans.Entry_Blocked_Missing_Entry,
               "missing source reports stable write decision");
         end;

         Requests.Clear;
         Requests.Append
           (Archive.Writes.Plans.Write_Request'
              (Action           => Archive.Writes.Plans.Replace_File,
               Source_Entry     => 2,
               Host_Source      => To_Unbounded_String ("host/replacement.txt"),
               Target_Path      => To_Unbounded_String ("safe/other.txt"),
               Replacement_Path => Null_Unbounded_String));
         declare
            Plan : constant Archive.Writes.Plans.Write_Plan :=
              Archive.Writes.Plans.Build (Index, Requests, Session => 7);
         begin
            Assert (Plan.Status = Archive.Writes.Plans.Write_Plan_Blocked,
                    "replace target must match selected archive entry");
            Assert
              (Plan.Changes.Element (1).Decision =
                 Archive.Writes.Plans.Entry_Blocked_Missing_Entry,
               "replace target mismatch reports stable write decision");
         end;

         Requests.Clear;
         Requests.Append
           (Archive.Writes.Plans.Write_Request'
              (Action           => Archive.Writes.Plans.Add_Directory,
               Source_Entry     => Archive.Types.No_Entry,
               Host_Source      => To_Unbounded_String ("host/safe"),
               Target_Path      => To_Unbounded_String ("safe"),
               Replacement_Path => Null_Unbounded_String));
         declare
            Plan : constant Archive.Writes.Plans.Write_Plan :=
              Archive.Writes.Plans.Build (Index, Requests, Session => 7);
         begin
            Assert (Plan.Status = Archive.Writes.Plans.Write_Plan_Has_Conflicts,
                    "add directory detects synthetic directory target conflicts");
            Assert
              (Plan.Changes.Element (1).Decision =
                 Archive.Writes.Plans.Entry_Conflict_Duplicate_Target,
               "directory target conflict reports stable write conflict");
         end;

         Requests.Clear;
         Requests.Append
           (Archive.Writes.Plans.Write_Request'
              (Action           => Archive.Writes.Plans.Remove_Entry,
               Source_Entry     => 2,
               Host_Source      => Null_Unbounded_String,
               Target_Path      => Null_Unbounded_String,
               Replacement_Path => Null_Unbounded_String));
         declare
            Plan : constant Archive.Writes.Plans.Write_Plan :=
              Archive.Writes.Plans.Build (Index, Requests, Session => 7);
         begin
            Assert (Plan.Status = Archive.Writes.Plans.Write_Plan_Ready,
                    "existing selected entry creates ready remove plan");
            Assert (Plan.Requested_Count = 1, "remove plan retains request count");
         end;

         Requests.Clear;
         Requests.Append
           (Archive.Writes.Plans.Write_Request'
              (Action           => Archive.Writes.Plans.Rename_Entry,
               Source_Entry     => 2,
               Host_Source      => Null_Unbounded_String,
               Target_Path      => Null_Unbounded_String,
               Replacement_Path => To_Unbounded_String ("safe/b.txt")));
         declare
            Plan : constant Archive.Writes.Plans.Write_Plan :=
              Archive.Writes.Plans.Build (Index, Requests, Session => 7);
         begin
            Assert (Plan.Status = Archive.Writes.Plans.Write_Plan_Has_Conflicts,
                    "rename to existing path creates write conflict");
            Assert
              (Plan.Changes.Element (1).Decision =
                 Archive.Writes.Plans.Entry_Conflict_Duplicate_Target,
               "rename duplicate target reports stable write conflict");
         end;

         Requests.Clear;
         Requests.Append
           (Archive.Writes.Plans.Write_Request'
              (Action           => Archive.Writes.Plans.Rename_Entry,
               Source_Entry     => 2,
               Host_Source      => Null_Unbounded_String,
               Target_Path      => Null_Unbounded_String,
               Replacement_Path => To_Unbounded_String ("safe/renamed.txt")));
         declare
            Plan : constant Archive.Writes.Plans.Write_Plan :=
              Archive.Writes.Plans.Build
                (Index, Requests, Session => Archive.Types.No_Generation);
         begin
            Assert (Plan.Status = Archive.Writes.Plans.Write_Plan_Blocked,
                    "no session generation blocks mutation plan");
            Assert
              (Plan.Changes.Element (1).Decision =
                 Archive.Writes.Plans.Entry_Blocked_No_Session,
               "no session reports stable write decision");
         end;

         Requests.Clear;
         Requests.Append
           (Archive.Writes.Plans.Write_Request'
              (Action           => Archive.Writes.Plans.Add_File,
               Source_Entry     => Archive.Types.No_Entry,
               Host_Source      => To_Unbounded_String ("host/case.txt"),
               Target_Path      => To_Unbounded_String ("SAFE/A.TXT"),
               Replacement_Path => Null_Unbounded_String));
         declare
            POSIX_Plan : constant Archive.Writes.Plans.Write_Plan :=
              Archive.Writes.Plans.Build
                (Index, Requests, Session => 7,
                 Platform => Archive.Extraction.Paths.POSIX_Path_Model);
            Windows_Plan : constant Archive.Writes.Plans.Write_Plan :=
              Archive.Writes.Plans.Build
                (Index, Requests, Session => 7,
                 Platform => Archive.Extraction.Paths.Windows_Path_Model);
         begin
            Assert (POSIX_Plan.Status = Archive.Writes.Plans.Write_Plan_Ready,
                    "posix write plan keeps case-distinct archive paths");
            Assert
              (Windows_Plan.Status = Archive.Writes.Plans.Write_Plan_Has_Conflicts
               and then Windows_Plan.Changes.Element (1).Decision =
                 Archive.Writes.Plans.Entry_Conflict_Duplicate_Target,
               "windows write plan catches case-folding target collisions");
         end;

         Requests.Clear;
         Requests.Append
           (Archive.Writes.Plans.Write_Request'
              (Action           => Archive.Writes.Plans.Add_File,
               Source_Entry     => Archive.Types.No_Entry,
               Host_Source      => To_Unbounded_String ("host/dup.txt"),
               Target_Path      => To_Unbounded_String ("safe/a.txt"),
               Replacement_Path => Null_Unbounded_String));
         Requests.Append
           (Archive.Writes.Plans.Write_Request'
              (Action           => Archive.Writes.Plans.Add_File,
               Source_Entry     => Archive.Types.No_Entry,
               Host_Source      => To_Unbounded_String ("host/new.txt"),
               Target_Path      => To_Unbounded_String ("safe/new"),
               Replacement_Path => Null_Unbounded_String));
         declare
            Ask_Plan : constant Archive.Writes.Plans.Write_Plan :=
              Archive.Writes.Plans.Build (Index, Requests, Session => 7);
            Rename_All_Plan : constant Archive.Writes.Plans.Write_Plan :=
              Archive.Writes.Plans.Build
                (Index, Requests, Session => 7,
                 Conflict_Action => Archive.Writes.Plans.Resolve_Rename,
                 Apply_To_All    => True);
         begin
            Assert
              (Ask_Plan.Status = Archive.Writes.Plans.Write_Plan_Has_Conflicts
               and then Ask_Plan.Auto_Resolved_Count = 0,
               "default write conflict policy keeps prompt-required conflicts");
            Assert
              (Rename_All_Plan.Status = Archive.Writes.Plans.Write_Plan_Ready
               and then Rename_All_Plan.Auto_Resolved_Count = 1,
               "apply-to-all rename policy marks duplicate conflicts resolved");
            Assert
              (Rename_All_Plan.Changes.Element (1).Resolution.Action =
                 Archive.Writes.Plans.Resolve_Rename
               and then Rename_All_Plan.Changes.Element (1).Resolution.Apply_To_All,
               "resolved write conflict retains stable apply-to-all decision");
         end;
      end;
   end Test_Write_Planning;

   procedure Test_Deterministic_Mutation_Gate (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      Root : constant String := "obj/deterministic-mutation-gate-test";
      Host_File : constant String := Root & "/input.txt";
      File : Ada.Streams.Stream_IO.File_Type;
      Host_Data : constant Ada.Streams.Stream_Element_Array :=
        [1 => Ada.Streams.Stream_Element (Character'Pos ('o')),
         2 => Ada.Streams.Stream_Element (Character'Pos ('k'))];
      Physical : Archive.Archives.Entries.Entry_Vectors.Vector;
      Requests : Archive.Writes.Plans.Write_Request_Vectors.Vector;

      function Entry_Id_For
        (Index : Archive.Archives.Index.Archive_Index;
         Path  : String)
         return Archive.Types.Entry_Id
      is
      begin
         for Raw_Id in 1 .. Archive.Archives.Index.Entry_Count (Index) loop
            declare
               Id   : constant Archive.Types.Entry_Id := Archive.Types.Entry_Id (Raw_Id);
               Item : constant Archive.Archives.Entries.Archive_Entry :=
                 Archive.Archives.Index.Entry_For (Index, Id);
            begin
               if To_String (Item.Original_Path) = Path then
                  return Id;
               end if;
            end;
         end loop;
         return Archive.Types.No_Entry;
      end Entry_Id_For;
   begin
      if not Ada.Directories.Exists (Root) then
         Ada.Directories.Create_Path (Root);
      end if;

      Ada.Streams.Stream_IO.Create (File, Ada.Streams.Stream_IO.Out_File, Host_File);
      Ada.Streams.Stream_IO.Write (File, Host_Data);
      Ada.Streams.Stream_IO.Close (File);

      Physical.Append (Fixture_Entry ("existing.txt"));
      Requests.Append
        (Archive.Writes.Plans.Write_Request'
           (Action           => Archive.Writes.Plans.Add_File,
            Source_Entry     => Archive.Types.No_Entry,
            Host_Source      => To_Unbounded_String (Host_File),
            Target_Path      => To_Unbounded_String ("new/file.txt"),
            Replacement_Path => Null_Unbounded_String));

      declare
         Build : constant Archive.Archives.Index.Build_Result :=
           Archive.Archives.Index.Build (Physical);
         Plan_A : constant Archive.Writes.Plans.Write_Plan :=
           Archive.Writes.Plans.Build (Build.Index, Requests, Session => 123);
         Plan_B : constant Archive.Writes.Plans.Write_Plan :=
           Archive.Writes.Plans.Build (Build.Index, Requests, Session => 123);
      begin
         Assert (Plan_A.Status = Plan_B.Status, "mutation planning status is deterministic");
         Assert (Plan_A.Requested_Count = Plan_B.Requested_Count, "mutation request count is deterministic");
         Assert (Natural (Plan_A.Changes.Length) = Natural (Plan_B.Changes.Length),
                 "mutation change count is deterministic");
         for Index in 1 .. Natural (Plan_A.Changes.Length) loop
            Assert
              (Plan_A.Changes.Element (Index).Decision =
                 Plan_B.Changes.Element (Index).Decision,
               "mutation decisions are deterministic");
         end loop;

         declare
            Zip_A_Path : constant String := Root & "/deterministic-a.zip";
            Zip_B_Path : constant String := Root & "/deterministic-b.zip";
            Tar_Gz_A_Path : constant String := Root & "/deterministic-a.tar.gz";
            Tar_Gz_B_Path : constant String := Root & "/deterministic-b.tar.gz";
            Zip_A : constant Archive.Writes.Results.Publish_Result :=
              Archive.Writes.Dispatch.Publish
                (Archive.Archives.Formats.Zip_Format, Zip_A_Path, Plan_A,
                 Method => Archive.Writes.Dispatch.Zip_Deflate_Method,
                 Overwrite => True);
            Zip_B : constant Archive.Writes.Results.Publish_Result :=
              Archive.Writes.Dispatch.Publish
                (Archive.Archives.Formats.Zip_Format, Zip_B_Path, Plan_B,
                 Method => Archive.Writes.Dispatch.Zip_Deflate_Method,
                 Overwrite => True);
            Tar_Gz_A : constant Archive.Writes.Results.Publish_Result :=
              Archive.Writes.Dispatch.Publish
                (Archive.Archives.Formats.Tar_GZip_Format, Tar_Gz_A_Path, Plan_A,
                 Overwrite => True);
            Tar_Gz_B : constant Archive.Writes.Results.Publish_Result :=
              Archive.Writes.Dispatch.Publish
                (Archive.Archives.Formats.Tar_GZip_Format, Tar_Gz_B_Path, Plan_B,
                 Overwrite => True);
         begin
            Assert (Zip_A.Status = Archive.Writes.Results.Write_Completed,
                    "zip mutation publish builds deterministically");
            Assert (Zip_A.Status = Zip_B.Status, "zip mutation status is deterministic");
            Assert (Read_All_Bytes (Zip_A_Path) = Read_All_Bytes (Zip_B_Path),
                    "zip mutation bytes are deterministic");
            Assert (Tar_Gz_A.Status = Archive.Writes.Results.Write_Completed,
                    "tar.gz mutation publish builds deterministically");
            Assert (Read_All_Bytes (Tar_Gz_A_Path) = Read_All_Bytes (Tar_Gz_B_Path),
                    "tar.gz mutation output bytes are deterministic");
         end;

         Requests.Append
           (Archive.Writes.Plans.Write_Request'
              (Action           => Archive.Writes.Plans.Rename_Entry,
               Source_Entry     => 2,
               Host_Source      => Null_Unbounded_String,
               Target_Path      => Null_Unbounded_String,
               Replacement_Path => To_Unbounded_String ("existing.txt")));
         declare
            Conflict_A : constant Archive.Writes.Plans.Write_Plan :=
              Archive.Writes.Plans.Build
                (Build.Index, Requests, Session => 123,
                 Platform => Archive.Extraction.Paths.Windows_Path_Model);
            Conflict_B : constant Archive.Writes.Plans.Write_Plan :=
              Archive.Writes.Plans.Build
                (Build.Index, Requests, Session => 123,
                 Platform => Archive.Extraction.Paths.Windows_Path_Model);
         begin
            Assert
              (Conflict_A.Status = Archive.Writes.Plans.Write_Plan_Has_Conflicts,
               "deterministic mutation conflict plan is explicit");
            Assert
              (Conflict_A.Changes.Element (2).Decision =
                 Conflict_B.Changes.Element (2).Decision,
               "deterministic mutation conflict decisions are stable");
         end;
      end;
   end Test_Deterministic_Mutation_Gate;

   function Read_All_Bytes (Path : String) return Zlib.Byte_Array is
      File : Ada.Streams.Stream_IO.File_Type;
      Size : constant Natural := Natural (Ada.Directories.Size (Path));
      Data : Ada.Streams.Stream_Element_Array (1 .. Ada.Streams.Stream_Element_Offset (Size));
      Last : Ada.Streams.Stream_Element_Offset := 0;
      Result : Zlib.Byte_Array (1 .. Size);
   begin
      Ada.Streams.Stream_IO.Open (File, Ada.Streams.Stream_IO.In_File, Path);
      Ada.Streams.Stream_IO.Read (File, Data, Last);
      Ada.Streams.Stream_IO.Close (File);
      for Index in Result'Range loop
         Result (Index) := Zlib.Byte (Data (Ada.Streams.Stream_Element_Offset (Index)));
      end loop;
      return Result;
   end Read_All_Bytes;

   function CRC32_Compute (Bytes : Zlib.Byte_Array) return Archive.Types.CRC32_Value is
      State : Archive.Verification.CRC32.CRC32_State := Archive.Verification.CRC32.Initial;
   begin
      Archive.Verification.CRC32.Update (State, Bytes);
      return Archive.Verification.CRC32.Final (State);
   end CRC32_Compute;

   function Fixture_Path
     (Name  : String;
      Bytes : Zlib.Byte_Array)
      return String
   is
      Root : constant String := "obj/byte-fixture-api";
      Safe_Name : String := Name;
   begin
      for C of Safe_Name loop
         if C = '/' or else C = '\' or else C = ':' then
            C := '_';
         end if;
      end loop;
      Ada.Directories.Create_Path (Root);
      Write_Bytes (Root & "/" & Safe_Name, Bytes);
      return Root & "/" & Safe_Name;
   end Fixture_Path;

   function Detect_Bytes
     (Bytes : Zlib.Byte_Array)
      return Archive.Archives.Formats.Detection_Result
   is
      Path : constant String := Fixture_Path ("detect.bin", Bytes);
   begin
      return Archive.Archives.Formats.Detect_File (Path);
   end Detect_Bytes;

   function Index_Zip
     (Bytes : Zlib.Byte_Array)
      return Archive.Archives.Readers.Zip.Zip_Index_Result
   is
      Path : constant String := Fixture_Path ("index.zip", Bytes);
   begin
      return Archive.Archives.Readers.Zip.Index_File (Path);
   end Index_Zip;

   function Index_Tar
     (Bytes : Zlib.Byte_Array)
      return Archive.Archives.Readers.Tar.Tar_Index_Result
   is
      Path : constant String := Fixture_Path ("index.tar", Bytes);
   begin
      return Archive.Archives.Readers.Tar.Index_File (Path);
   end Index_Tar;

   function Index_Gzip
     (Bytes       : Zlib.Byte_Array;
      Source_Name : String := "")
      return Archive.Archives.Readers.Gzip.Gzip_Index_Result
   is
      Path : constant String := Fixture_Path
        ((if Source_Name'Length > 0 then Source_Name else "index.gz"), Bytes);
   begin
      return Archive.Archives.Readers.Gzip.Index_File (Path, Source_Name);
   end Index_Gzip;

   function Open_Dispatch
     (Bytes       : Zlib.Byte_Array;
      Source_Name : String := "")
      return Archive.Archives.Readers.Dispatch.Open_Result
   is
      Path : constant String := Fixture_Path
        ((if Source_Name'Length > 0 then Source_Name else "dispatch.bin"), Bytes);
   begin
      return Archive.Archives.Readers.Dispatch.Open_File (Path, Source_Name => Source_Name);
   end Open_Dispatch;

   function Byte_Vector (Bytes : Zlib.Byte_Array) return Test_Byte_Vectors.Vector is
      Result : Test_Byte_Vectors.Vector;
   begin
      for Byte of Bytes loop
         Result.Append (Byte);
      end loop;
      return Result;
   end Byte_Vector;

   function Bytes_Of (Result : Test_Zlib_Result) return Zlib.Byte_Array is
      Bytes : Zlib.Byte_Array (1 .. Natural (Result.Bytes.Length));
      Pos   : Natural := 1;
   begin
      for Byte of Result.Bytes loop
         Bytes (Pos) := Byte;
         Pos := Pos + 1;
      end loop;
      return Bytes;
   end Bytes_Of;

   function Byte_Length (Result : Test_Zlib_Result) return Natural is
   begin
      return Natural (Result.Bytes.Length);
   end Byte_Length;

   function Byte_Length
     (Result : Archive.Archives.Streams.Buffered_Source)
      return Natural
   is
   begin
      return Result.Bytes'Length;
   end Byte_Length;

   function Byte_Length
     (Result : Archive.Source_Monitoring.Probe_Result)
      return Natural
   is
   begin
      return Result.Bytes'Length;
   end Byte_Length;

   procedure Append_Test_Zlib_Output
     (Bytes  : Zlib.Byte_Array;
      Output : in out Zlib.Byte_Array;
      Used   : in out Natural)
   is
      pragma Unreferenced (Output);
      pragma Unreferenced (Used);
   begin
      null;
   end Append_Test_Zlib_Output;

   function Test_Inflate_Streaming
     (Input : Zlib.Byte_Array;
      Mode  : Archive.Compression.Zlib.Stream_Mode;
      Limits : Archive.Compression.Zlib.Inflate_Limits := (others => <>);
      Input_Chunk_Bytes  : Positive := 1_024;
      Output_Chunk_Bytes : Positive := 1_024;
      Cancellation : access Archive.Tasking.Cancellation.Token := null)
      return Test_Zlib_Result
   is
      Header : constant Zlib.Header_Type :=
        (case Mode is
            when Archive.Compression.Zlib.Raw_Deflate => Zlib.Raw_Deflate,
            when Archive.Compression.Zlib.Zlib_Wrapped => Zlib.Zlib_Header,
            when Archive.Compression.Zlib.Gzip_Wrapped => Zlib.GZip,
            when Archive.Compression.Zlib.Auto_Wrapped => Zlib.Default);
      Status : Zlib.Status_Code;
      Consumed : Natural := Input'Length;
   begin
      if Cancellation /= null and then Cancellation.Cancelled then
         return
           (Status => Archive.Archives.Errors.Cancelled,
            Compressed_Bytes => 0,
            Uncompressed_Bytes => 0,
            Input_Bytes => 0,
            Output_Bytes => 0,
            Input_Chunks => 0,
            Output_Chunks => 0,
            Unused_Input_Bytes => Archive.Types.Compressed_Size (Input'Length),
            Stream_Ended => False,
            Output_Limited => False,
            Ratio_Limited => False,
            Cancelled => True,
            Bytes => Test_Byte_Vectors.Empty_Vector);
      end if;

      declare
         function Decode (Length : Natural; Out_Status : out Zlib.Status_Code)
            return Zlib.Byte_Array
         is
            Slice : Zlib.Byte_Array (1 .. Length);
         begin
            for Index in Slice'Range loop
               Slice (Index) := Input (Input'First + Index - 1);
            end loop;
            return Zlib.Inflate_With_Header (Slice, Header, Out_Status);
         end Decode;

         Output : Zlib.Byte_Array := Decode (Input'Length, Status);
      begin
         if Mode = Archive.Compression.Zlib.Raw_Deflate then
            declare
               Full_Status : constant Zlib.Status_Code := Status;
               Found       : Boolean := False;
            begin
               for Candidate in 1 .. Input'Length - 1 loop
                  declare
                     Candidate_Output : constant Zlib.Byte_Array := Decode (Candidate, Status);
                  begin
                     if Status = Zlib.Ok and then Candidate_Output = Output then
                        Output := Candidate_Output;
                        Consumed := Candidate;
                        Found := True;
                        exit;
                     end if;
                  end;
               end loop;
               if not Found then
                  Status := Full_Status;
               end if;
            end;
         end if;

         if Status = Zlib.Ok
           and then Archive.Types.Uncompressed_Size (Output'Length) >
             Limits.Max_Output_Bytes
         then
            return
              (Status => Archive.Archives.Errors.Limit_Exceeded,
               Compressed_Bytes => Archive.Types.Compressed_Size (Consumed),
               Uncompressed_Bytes => Archive.Types.Uncompressed_Size (Output'Length),
               Input_Bytes => Archive.Types.Uncompressed_Size (Consumed),
               Output_Bytes => Archive.Types.Compressed_Size (Output'Length),
               Input_Chunks => (Input'Length + Input_Chunk_Bytes - 1) / Input_Chunk_Bytes,
               Output_Chunks => 0,
               Unused_Input_Bytes => Archive.Types.Compressed_Size (Input'Length - Consumed),
               Stream_Ended => False,
               Output_Limited => True,
               Ratio_Limited => False,
               Cancelled => False,
               Bytes => Test_Byte_Vectors.Empty_Vector);
         elsif Status = Zlib.Ok
           and then Consumed > 0
           and then Archive.Types.Uncompressed_Size (Output'Length) /
             Archive.Types.Uncompressed_Size (Consumed) >
               Archive.Types.Uncompressed_Size (Limits.Max_Ratio)
         then
            return
              (Status => Archive.Archives.Errors.Limit_Exceeded,
               Compressed_Bytes => Archive.Types.Compressed_Size (Consumed),
               Uncompressed_Bytes => Archive.Types.Uncompressed_Size (Output'Length),
               Input_Bytes => Archive.Types.Uncompressed_Size (Consumed),
               Output_Bytes => Archive.Types.Compressed_Size (Output'Length),
               Input_Chunks => (Input'Length + Input_Chunk_Bytes - 1) / Input_Chunk_Bytes,
               Output_Chunks => 0,
               Unused_Input_Bytes => Archive.Types.Compressed_Size (Input'Length - Consumed),
               Stream_Ended => False,
               Output_Limited => False,
               Ratio_Limited => True,
               Cancelled => False,
               Bytes => Test_Byte_Vectors.Empty_Vector);
         end if;

         return
           (Status =>
              Archive.Compression.Zlib.Map_Status (Status),
            Compressed_Bytes => Archive.Types.Compressed_Size (Consumed),
            Uncompressed_Bytes =>
              (if Status = Zlib.Ok
               then Archive.Types.Uncompressed_Size (Output'Length)
               else 0),
            Input_Bytes => Archive.Types.Uncompressed_Size (Consumed),
            Output_Bytes =>
              (if Status = Zlib.Ok
               then Archive.Types.Compressed_Size (Output'Length)
               else 0),
            Input_Chunks => (Input'Length + Input_Chunk_Bytes - 1) / Input_Chunk_Bytes,
            Output_Chunks =>
              (if Status = Zlib.Ok
               then Natural'Max (1, (Output'Length + Output_Chunk_Bytes - 1) / Output_Chunk_Bytes)
               else 0),
            Unused_Input_Bytes => Archive.Types.Compressed_Size (Input'Length - Consumed),
            Stream_Ended => Status = Zlib.Ok,
            Output_Limited => False,
            Ratio_Limited => False,
            Cancelled => False,
            Bytes =>
              (if Status = Zlib.Ok
               then Byte_Vector (Output)
               else Test_Byte_Vectors.Empty_Vector));
      end;
   end Test_Inflate_Streaming;

   function Test_Inflate
     (Input : Zlib.Byte_Array;
      Mode  : Archive.Compression.Zlib.Stream_Mode;
      Limits : Archive.Compression.Zlib.Inflate_Limits := (others => <>);
      Cancellation : access Archive.Tasking.Cancellation.Token := null)
      return Test_Zlib_Result
   is
   begin
      return Test_Inflate_Streaming
        (Input, Mode, Limits, Cancellation => Cancellation);
   end Test_Inflate;

   function Test_Deflate_Streaming
     (Input : Zlib.Byte_Array;
      Mode  : Archive.Compression.Zlib.Stream_Mode;
      Max_Output_Bytes : Archive.Types.Compressed_Size :=
        Archive.Types.Compressed_Size
          (Archive.Resource_Limits.Default_Configured
             (Archive.Resource_Limits.Temporary_Backing_Bytes));
      Input_Chunk_Bytes  : Positive := 1_024;
      Output_Chunk_Bytes : Positive := 1_024;
      Cancellation : access Archive.Tasking.Cancellation.Token := null)
      return Test_Zlib_Result
   is
      Status : Zlib.Status_Code;
   begin
      if Cancellation /= null and then Cancellation.Cancelled then
         return
           (Status => Archive.Archives.Errors.Cancelled,
            Compressed_Bytes => 0,
            Uncompressed_Bytes => Archive.Types.Uncompressed_Size (Input'Length),
            Input_Bytes => Archive.Types.Uncompressed_Size (Input'Length),
            Output_Bytes => 0,
            Input_Chunks => 0,
            Output_Chunks => 0,
            Unused_Input_Bytes => 0,
            Stream_Ended => False,
            Output_Limited => False,
            Ratio_Limited => False,
            Cancelled => True,
            Bytes => Test_Byte_Vectors.Empty_Vector);
      end if;

      declare
         pragma Warnings (Off, "*useless assignment to*Status*");
         Output : constant Zlib.Byte_Array :=
           (case Mode is
              when Archive.Compression.Zlib.Raw_Deflate =>
                 Zlib.Deflate_Raw (Input, Zlib.Fixed, Status),
              when Archive.Compression.Zlib.Zlib_Wrapped |
                   Archive.Compression.Zlib.Auto_Wrapped =>
                 Zlib.Deflate (Input, Zlib.Fixed, Status),
              when Archive.Compression.Zlib.Gzip_Wrapped =>
                 Zlib.GZip (Input, Zlib.Fixed, Status));
         pragma Warnings (On, "*useless assignment to*Status*");
      begin
         if Status = Zlib.Ok
           and then Archive.Types.Compressed_Size (Output'Length) > Max_Output_Bytes
         then
            return
              (Status => Archive.Archives.Errors.Limit_Exceeded,
               Compressed_Bytes => Archive.Types.Compressed_Size (Output'Length),
               Uncompressed_Bytes => Archive.Types.Uncompressed_Size (Input'Length),
               Input_Bytes => Archive.Types.Uncompressed_Size (Input'Length),
               Output_Bytes => Archive.Types.Compressed_Size (Output'Length),
               Input_Chunks => (Input'Length + Input_Chunk_Bytes - 1) / Input_Chunk_Bytes,
               Output_Chunks => 0,
               Unused_Input_Bytes => 0,
               Stream_Ended => False,
               Output_Limited => True,
               Ratio_Limited => False,
               Cancelled => False,
               Bytes => Test_Byte_Vectors.Empty_Vector);
         end if;

         return
           (Status => Archive.Compression.Zlib.Map_Status (Status),
            Compressed_Bytes =>
              (if Status = Zlib.Ok
               then Archive.Types.Compressed_Size (Output'Length)
               else 0),
            Uncompressed_Bytes => Archive.Types.Uncompressed_Size (Input'Length),
            Input_Bytes => Archive.Types.Uncompressed_Size (Input'Length),
            Output_Bytes =>
              (if Status = Zlib.Ok
               then Archive.Types.Compressed_Size (Output'Length)
               else 0),
            Input_Chunks => (Input'Length + Input_Chunk_Bytes - 1) / Input_Chunk_Bytes,
            Output_Chunks =>
              (if Status = Zlib.Ok
               then Natural'Max (1, (Output'Length + Output_Chunk_Bytes - 1) / Output_Chunk_Bytes)
               else 0),
            Unused_Input_Bytes => 0,
            Stream_Ended => Status = Zlib.Ok,
            Output_Limited => False,
            Ratio_Limited => False,
            Cancelled => False,
            Bytes =>
              (if Status = Zlib.Ok
               then Byte_Vector (Output)
               else Test_Byte_Vectors.Empty_Vector));
      end;
   end Test_Deflate_Streaming;

   function Test_Deflate
     (Input : Zlib.Byte_Array;
      Mode  : Archive.Compression.Zlib.Stream_Mode;
      Max_Output_Bytes : Archive.Types.Compressed_Size :=
        Archive.Types.Compressed_Size
          (Archive.Resource_Limits.Default_Configured
             (Archive.Resource_Limits.Temporary_Backing_Bytes));
      Cancellation : access Archive.Tasking.Cancellation.Token := null)
      return Test_Zlib_Result
   is
   begin
      return Test_Deflate_Streaming
        (Input, Mode, Max_Output_Bytes, Cancellation => Cancellation);
   end Test_Deflate;

   procedure Record_Test_Stream_Chunk
     (Target : in out Test_Stream_Result;
      Chunk  : Zlib.Byte_Array)
   is
   begin
      Target.Bytes_Written := Target.Bytes_Written + Chunk'Length;
      for Byte of Chunk loop
         exit when Target.Prefix_Length = Target.Bytes'Length;
         Target.Prefix_Length := Target.Prefix_Length + 1;
         Target.Bytes (Target.Prefix_Length) := Byte;
      end loop;
   end Record_Test_Stream_Chunk;

   function Bytes_Of (Result : Test_Stream_Result) return Zlib.Byte_Array is
   begin
      return Result.Bytes;
   end Bytes_Of;

   function Byte_Length (Result : Test_Stream_Result) return Natural is
   begin
      return Result.Bytes'Length;
   end Byte_Length;

   function Empty_Test_Stream
     (Status    : Archive.Archives.Errors.Error_Code;
      Integrity : Archive.Archives.Entries.Integrity_State :=
        Archive.Archives.Entries.Not_Available)
      return Test_Stream_Result
   is
   begin
      return (Status => Status,
              Integrity => Integrity,
              Bytes_Written => 0,
              Prefix_Length => 0,
              Bytes => [others => 0]);
   end Empty_Test_Stream;

   function Stream_Dispatch_Payload_File
     (Path        : String;
      Source_Name : String;
      Item        : Archive.Archives.Entries.Archive_Entry)
      return Test_Stream_Result
   is
      Result : Test_Stream_Result;

      procedure Consume
        (Chunk : Zlib.Byte_Array;
         Continue : in out Boolean)
      is
      begin
         Record_Test_Stream_Chunk (Result, Chunk);
         Continue := True;
      end Consume;

      Streamed : constant Archive.Archives.Readers.Dispatch.Stream_Result :=
        Archive.Archives.Readers.Dispatch.Stream_Payload_File
          (Path, Source_Name, Item, Consume'Access);
   begin
      if Streamed.Status /= Archive.Archives.Errors.Ok then
         return Empty_Test_Stream (Streamed.Status, Streamed.Integrity);
      end if;
      Result.Status := Streamed.Status;
      Result.Integrity := Streamed.Integrity;
      return Result;
   end Stream_Dispatch_Payload_File;

   function Stream_Dispatch_Payload
     (Bytes       : Zlib.Byte_Array;
      Source_Name : String;
      Item        : Archive.Archives.Entries.Archive_Entry)
      return Test_Stream_Result
   is
      Root : constant String := "obj/reader-stream-fixtures";
      Path : constant String := Root & "/dispatch.bin";
   begin
      Ada.Directories.Create_Path (Root);
      Write_Bytes (Path, Bytes);
      return Stream_Dispatch_Payload_File (Path, Source_Name, Item);
   end Stream_Dispatch_Payload;

   function Stream_Zip_Payload_File
     (Path : String;
      Item : Archive.Archives.Entries.Archive_Entry)
      return Test_Stream_Result
   is
      Result : Test_Stream_Result;

      procedure Consume
        (Chunk : Zlib.Byte_Array;
         Continue : in out Boolean)
      is
      begin
         Record_Test_Stream_Chunk (Result, Chunk);
         Continue := True;
      end Consume;

      Streamed : constant Archive.Archives.Readers.Zip.Stream_Result :=
        Archive.Archives.Readers.Zip.Stream_Payload_File (Path, Item, Consume'Access);
   begin
      if Streamed.Status /= Archive.Archives.Errors.Ok then
         return Empty_Test_Stream (Streamed.Status, Streamed.Integrity);
      end if;
      Result.Status := Streamed.Status;
      Result.Integrity := Streamed.Integrity;
      return Result;
   end Stream_Zip_Payload_File;

   function Stream_Zip_Payload
     (Bytes : Zlib.Byte_Array;
      Item  : Archive.Archives.Entries.Archive_Entry)
      return Test_Stream_Result
   is
      Root : constant String := "obj/reader-stream-fixtures";
      Path : constant String := Root & "/payload.zip";
   begin
      Ada.Directories.Create_Path (Root);
      Write_Bytes (Path, Bytes);
      return Stream_Zip_Payload_File (Path, Item);
   end Stream_Zip_Payload;

   function Stream_Tar_Payload_File
     (Path : String;
      Item : Archive.Archives.Entries.Archive_Entry)
      return Test_Stream_Result
   is
      Result : Test_Stream_Result;

      procedure Consume
        (Chunk : Zlib.Byte_Array;
         Continue : in out Boolean)
      is
      begin
         Record_Test_Stream_Chunk (Result, Chunk);
         Continue := True;
      end Consume;

      Streamed : constant Archive.Archives.Readers.Tar.Stream_Result :=
        Archive.Archives.Readers.Tar.Stream_Payload_File (Path, Item, Consume'Access);
   begin
      if Streamed.Status /= Archive.Archives.Errors.Ok then
         return Empty_Test_Stream (Streamed.Status, Streamed.Integrity);
      end if;
      Result.Status := Streamed.Status;
      Result.Integrity := Streamed.Integrity;
      return Result;
   end Stream_Tar_Payload_File;

   function Stream_Tar_Payload
     (Bytes : Zlib.Byte_Array;
      Item  : Archive.Archives.Entries.Archive_Entry)
      return Test_Stream_Result
   is
      Root : constant String := "obj/reader-stream-fixtures";
      Path : constant String := Root & "/payload.tar";
   begin
      Ada.Directories.Create_Path (Root);
      Write_Bytes (Path, Bytes);
      return Stream_Tar_Payload_File (Path, Item);
   end Stream_Tar_Payload;

   function Stream_Gzip_Payload
     (Bytes : Zlib.Byte_Array;
      Item  : Archive.Archives.Entries.Archive_Entry)
      return Test_Stream_Result
   is
      Root : constant String := "obj/reader-stream-fixtures";
      Path : constant String := Root & "/payload.gz";
   begin
      Ada.Directories.Create_Path (Root);
      Write_Bytes (Path, Bytes);
      return Stream_Dispatch_Payload_File (Path, "payload.gz", Item);
   end Stream_Gzip_Payload;

   procedure Test_Write_Execution (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      Root : constant String := "obj/write-execution-test";
      Target : constant String := Root & "/sample.zip";
      Payload : constant Zlib.Byte_Array := One_File_Zip;
      Payload_Path : constant String := Root & "/payload-source.zip";
      Replacement : constant Zlib.Byte_Array :=
        One_File_Zip
          (Data_Descriptor => True,
           Central_Comment_Length => 2,
           Archive_Comment_Length => 2);
      Replacement_Path : constant String := Root & "/replacement-source.zip";
      Invalid_Payload : constant Zlib.Byte_Array :=
        [1 => Zlib.Byte (Character'Pos ('z')),
         2 => Zlib.Byte (Character'Pos ('i')),
         3 => Zlib.Byte (Character'Pos ('p'))];
      Invalid_Payload_Path : constant String := Root & "/invalid-source.zip";
      Empty_Physical : Archive.Archives.Entries.Entry_Vectors.Vector;
      Empty_Index : constant Archive.Archives.Index.Archive_Index :=
        Archive.Archives.Index.Build (Empty_Physical).Index;
      Ready : constant Archive.Writes.Plans.Write_Plan :=
        (Status          => Archive.Writes.Plans.Write_Plan_Ready,
         Session         => 7,
         Index           => Empty_Index,
         Changes         => Archive.Writes.Plans.Planned_Change_Vectors.Empty_Vector,
         Requested_Count => 0,
         Blocked_Count   => 0,
         Conflict_Count  => 0,
         Duplicate_Target_Count => 0,
         File_Directory_Conflict_Count => 0,
         Auto_Resolved_Count => 0);
      Blocked : constant Archive.Writes.Plans.Write_Plan :=
        (Status          => Archive.Writes.Plans.Write_Plan_Blocked,
         Session         => 7,
         Index           => Empty_Index,
         Changes         => Archive.Writes.Plans.Planned_Change_Vectors.Empty_Vector,
         Requested_Count => 1,
         Blocked_Count   => 1,
         Conflict_Count  => 0,
         Duplicate_Target_Count => 0,
         File_Directory_Conflict_Count => 0,
         Auto_Resolved_Count => 0);
   begin
      if Ada.Directories.Exists (Target) then
         Ada.Directories.Delete_File (Target);
      end if;
      if not Ada.Directories.Exists (Root) then
         Ada.Directories.Create_Path (Root);
      end if;
      Write_Bytes (Payload_Path, Payload);
      Write_Bytes (Replacement_Path, Replacement);
      Write_Bytes (Invalid_Payload_Path, Invalid_Payload);

      declare
         Result : constant Archive.Writes.Results.Publish_Result :=
           Archive.Writes.Execution.Publish_Archive_From_File
             (Target,
              Blocked,
              Payload_Path,
              Expected_Format => Archive.Archives.Formats.Zip_Format,
              Source_Name     => "sample.zip");
      begin
         Assert (Result.Status = Archive.Writes.Results.Write_Blocked_By_Plan,
                 "blocked write plan does not publish archive");
      end;

      declare
         Result : constant Archive.Writes.Results.Publish_Result :=
           Archive.Writes.Execution.Publish_Archive_From_File
             (Target,
              Ready,
              Payload_Path,
              Expected_Format => Archive.Archives.Formats.Zip_Format,
              Source_Name     => "sample.zip");
         Written : constant Zlib.Byte_Array := Read_All_Bytes (Target);
      begin
         Assert (Result.Status = Archive.Writes.Results.Write_Completed,
                 "ready write plan publishes archive");
         Assert
           (Written'Length = Payload'Length
            and then Written (1) = Payload (1)
            and then Written (2) = Payload (2)
            and then Written (3) = Payload (3)
            and then Written (Written'Last) = Payload (Payload'Last),
            "published archive contains staged payload");
      end;

      declare
         File_Target : constant String := Root & "/file-backed.zip";
      begin
         if Ada.Directories.Exists (File_Target) then
            Ada.Directories.Delete_File (File_Target);
         end if;
         declare
            Result : constant Archive.Writes.Results.Publish_Result :=
              Archive.Writes.Execution.Publish_Archive_From_File
                (File_Target,
                 Ready,
                 Payload_Path,
                 Expected_Format => Archive.Archives.Formats.Zip_Format,
                 Source_Name     => "file-backed.zip");
            Written : constant Zlib.Byte_Array := Read_All_Bytes (File_Target);
         begin
            Assert (Result.Status = Archive.Writes.Results.Write_Completed,
                    "file-backed publisher completes");
            Assert
              (Written'Length = Payload'Length
               and then Written (1) = Payload (1)
               and then Written (Written'Last) = Payload (Payload'Last),
               "file-backed publisher copies source archive bytes");
         end;
      end;

      declare
         Missing_Target : constant String := Root & "/missing-file-backed.zip";
         Result : constant Archive.Writes.Results.Publish_Result :=
           Archive.Writes.Execution.Publish_Archive_From_File
             (Missing_Target,
              Ready,
              Root & "/missing-payload.zip",
              Expected_Format => Archive.Archives.Formats.Zip_Format,
              Source_Name     => "missing-file-backed.zip");
      begin
         Assert (Result.Status = Archive.Writes.Results.Write_Failed_Staging,
                 "missing file-backed payload fails during staging");
         Assert (not Ada.Directories.Exists (Missing_Target),
                 "missing file-backed payload does not publish destination");
      end;

      declare
         Result : constant Archive.Writes.Results.Publish_Result :=
           Archive.Writes.Execution.Publish_Archive_From_File
             (Target,
              Ready,
              Replacement_Path,
              Expected_Format => Archive.Archives.Formats.Zip_Format,
              Source_Name     => "sample.zip");
         Written : constant Zlib.Byte_Array := Read_All_Bytes (Target);
      begin
         Assert (Result.Status = Archive.Writes.Results.Write_Blocked_By_Plan,
                 "existing archive blocks without overwrite");
         Assert
           (Written'Length = Payload'Length
            and then Written (1) = Payload (1)
            and then Written (Written'Last) = Payload (Payload'Last),
            "blocked archive overwrite preserves previous payload");
      end;

      declare
         Result : constant Archive.Writes.Results.Publish_Result :=
           Archive.Writes.Execution.Publish_Archive_From_File
             (Target,
              Ready,
              Replacement_Path,
              Overwrite       => True,
              Expected_Format => Archive.Archives.Formats.Zip_Format,
              Source_Name     => "sample.zip");
         Written : constant Zlib.Byte_Array := Read_All_Bytes (Target);
      begin
         Assert (Result.Status = Archive.Writes.Results.Write_Completed,
                 "explicit overwrite publishes replacement archive");
         Assert
           (Written'Length = Replacement'Length
            and then Written (1) = Replacement (1)
            and then Written (2) = Replacement (2)
            and then Written (Written'Last) = Replacement (Replacement'Last),
            "overwrite replaces archive payload");
      end;

      declare
         Before : constant Zlib.Byte_Array := Read_All_Bytes (Target);
         Result : constant Archive.Writes.Results.Publish_Result :=
           Archive.Writes.Execution.Publish_Archive_From_File
             (Target,
              Ready,
              Invalid_Payload_Path,
              Overwrite       => True,
              Expected_Format => Archive.Archives.Formats.Zip_Format,
              Source_Name     => "sample.zip");
         After : constant Zlib.Byte_Array := Read_All_Bytes (Target);
      begin
         Assert (Result.Status = Archive.Writes.Results.Write_Failed_Verification,
                 "invalid staged archive is rejected before publication");
         Assert
           (After'Length = Before'Length
            and then After (1) = Before (1)
            and then After (After'Last) = Before (Before'Last),
            "failed staged verification preserves existing archive");
      end;

      declare
         Cancel_Target : constant String := Root & "/cancelled.zip";
         Temp_Target : constant String := Cancel_Target & ".archive-save-7.tmp";
         Result : constant Archive.Writes.Results.Publish_Result :=
           Archive.Writes.Execution.Publish_Archive_From_File
             (Cancel_Target,
              Ready,
              Payload_Path,
              Expected_Format => Archive.Archives.Formats.Zip_Format,
              Source_Name     => "cancelled.zip",
              Cancelled       => True);
      begin
         Assert (Result.Status = Archive.Writes.Results.Write_Cancelled,
                 "cancelled write does not publish archive");
         Assert (not Ada.Directories.Exists (Cancel_Target),
                 "cancelled write leaves no destination archive");
         Assert (not Ada.Directories.Exists (Temp_Target),
                 "cancelled write leaves no staged archive");
      end;
   end Test_Write_Execution;

   procedure Test_Tar_Write_Adapter (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      Root : constant String := "obj/tar-write-adapter-test";
      Host_File : constant String := Root & "/input.txt";
      Host_File_2 : constant String := Root & "/input-2.txt";
      File : Ada.Streams.Stream_IO.File_Type;
      Data : constant Ada.Streams.Stream_Element_Array :=
        [1 => Ada.Streams.Stream_Element (Character'Pos ('o')),
         2 => Ada.Streams.Stream_Element (Character'Pos ('k'))];
      Data_2 : constant Ada.Streams.Stream_Element_Array :=
        [1 => Ada.Streams.Stream_Element (Character'Pos ('n')),
         2 => Ada.Streams.Stream_Element (Character'Pos ('o'))];
      Physical : Archive.Archives.Entries.Entry_Vectors.Vector;
      Requests : Archive.Writes.Plans.Write_Request_Vectors.Vector;

      function Entry_Id_For
        (Index : Archive.Archives.Index.Archive_Index;
         Path  : String)
         return Archive.Types.Entry_Id
      is
      begin
         for Raw_Id in 1 .. Archive.Archives.Index.Entry_Count (Index) loop
            declare
               Id   : constant Archive.Types.Entry_Id := Archive.Types.Entry_Id (Raw_Id);
               Item : constant Archive.Archives.Entries.Archive_Entry :=
                 Archive.Archives.Index.Entry_For (Index, Id);
            begin
               if To_String (Item.Original_Path) = Path then
                  return Id;
               end if;
            end;
         end loop;
         return Archive.Types.No_Entry;
      end Entry_Id_For;
   begin
      if not Ada.Directories.Exists (Root) then
         Ada.Directories.Create_Path (Root);
      end if;

      Ada.Streams.Stream_IO.Create (File, Ada.Streams.Stream_IO.Out_File, Host_File);
      Ada.Streams.Stream_IO.Write (File, Data);
      Ada.Streams.Stream_IO.Close (File);
      Ada.Streams.Stream_IO.Create (File, Ada.Streams.Stream_IO.Out_File, Host_File_2);
      Ada.Streams.Stream_IO.Write (File, Data_2);
      Ada.Streams.Stream_IO.Close (File);

      Requests.Append
        (Archive.Writes.Plans.Write_Request'
           (Action           => Archive.Writes.Plans.Add_File,
            Source_Entry     => Archive.Types.No_Entry,
            Host_Source      => To_Unbounded_String (Host_File),
            Target_Path      => To_Unbounded_String ("docs/readme.txt"),
            Replacement_Path => Null_Unbounded_String));

      declare
         Index : constant Archive.Archives.Index.Archive_Index :=
           Archive.Archives.Index.Build (Physical).Index;
         Plan : constant Archive.Writes.Plans.Write_Plan :=
           Archive.Writes.Plans.Build (Index, Requests, Session => 7);
         Tar_Path : constant String := Root & "/payload-free.tar";
         Published : constant Archive.Writes.Results.Publish_Result :=
           Archive.Writes.Execution.Publish_Tar (Tar_Path, Plan, Overwrite => True);
         Parsed : constant Archive.Archives.Readers.Tar.Tar_Index_Result :=
           Archive.Archives.Readers.Tar.Index_File (Tar_Path);
         Readback : constant Test_Stream_Result :=
           Stream_Tar_Payload_File (Tar_Path, Parsed.Entries.Element (1));
      begin
         Assert (Plan.Status = Archive.Writes.Plans.Write_Plan_Ready, "tar write plan is ready");
         Assert (Published.Status = Archive.Writes.Results.Write_Completed,
                 "tar writer streams archive through tarlib");
         Assert (Parsed.Status = Archive.Archives.Errors.Ok, "written tar reopens through tarlib reader");
         Assert (Natural (Parsed.Entries.Length) = 1, "written tar contains one physical entry");
         Assert
           (Readback.Status = Archive.Archives.Errors.Ok
            and then Readback.Bytes_Written = 2
            and then Bytes_Of (Readback) (1) = Zlib.Byte (Character'Pos ('o'))
            and then Bytes_Of (Readback) (2) = Zlib.Byte (Character'Pos ('k')),
            "written tar payload round-trips");
      end;

      if Ada.Directories.Exists (Root & "/streamed.tar") then
         Ada.Directories.Delete_File (Root & "/streamed.tar");
      end if;

      declare
         Index : constant Archive.Archives.Index.Archive_Index :=
           Archive.Archives.Index.Build (Physical).Index;
         Plan : constant Archive.Writes.Plans.Write_Plan :=
           Archive.Writes.Plans.Build (Index, Requests, Session => 8);
         Tar_Path : constant String := Root & "/streamed.tar";
         Published : constant Archive.Writes.Results.Publish_Result :=
           Archive.Writes.Execution.Publish_Tar (Tar_Path, Plan);
         Parsed : constant Archive.Archives.Readers.Dispatch.Open_Result :=
           Archive.Archives.Readers.Dispatch.Open_File (Tar_Path, Max_Bytes => 1);
      begin
         Assert (Published.Status = Archive.Writes.Results.Write_Completed,
                 "streaming tar publisher completes");
         Assert
           (Parsed.Status = Archive.Archives.Errors.Ok
            and then Parsed.Format = Archive.Archives.Formats.Tar_Format
            and then Entry_Id_For (Parsed.Index, "docs/readme.txt") /= Archive.Types.No_Entry,
            "streaming tar publisher output opens through file-backed tarlib reader");
      end;

      if Ada.Directories.Exists (Root & "/streamed.tar.gz") then
         Ada.Directories.Delete_File (Root & "/streamed.tar.gz");
      end if;

      declare
         Index : constant Archive.Archives.Index.Archive_Index :=
           Archive.Archives.Index.Build (Physical).Index;
         Plan : constant Archive.Writes.Plans.Write_Plan :=
           Archive.Writes.Plans.Build (Index, Requests, Session => 9);
         Tar_Gz_Path : constant String := Root & "/streamed.tar.gz";
         Published : constant Archive.Writes.Results.Publish_Result :=
           Archive.Writes.Execution.Publish_Tar_Gzip (Tar_Gz_Path, Plan);
         Parsed : constant Archive.Archives.Readers.Dispatch.Open_Result :=
           Archive.Archives.Readers.Dispatch.Open_File
             (Tar_Gz_Path, Max_Bytes => 4096, Source_Name => Tar_Gz_Path);
      begin
         Assert (Published.Status = Archive.Writes.Results.Write_Completed,
                 "streaming tar.gz publisher completes");
         Assert
           (Parsed.Status = Archive.Archives.Errors.Ok
            and then Parsed.Format = Archive.Archives.Formats.Tar_GZip_Format
            and then Entry_Id_For (Parsed.Index, "docs/readme.txt") /= Archive.Types.No_Entry,
            "streaming tar.gz publisher output opens through gzip and tarlib readers");
      end;

      Requests.Clear;
      Requests.Append
        (Archive.Writes.Plans.Write_Request'
           (Action           => Archive.Writes.Plans.Add_File,
            Source_Entry     => Archive.Types.No_Entry,
            Host_Source      => To_Unbounded_String (Host_File),
            Target_Path      => To_Unbounded_String ("docs/a.txt"),
            Replacement_Path => Null_Unbounded_String));
      Requests.Append
        (Archive.Writes.Plans.Write_Request'
           (Action           => Archive.Writes.Plans.Add_File,
            Source_Entry     => Archive.Types.No_Entry,
            Host_Source      => To_Unbounded_String (Host_File_2),
            Target_Path      => To_Unbounded_String ("docs/b.txt"),
            Replacement_Path => Null_Unbounded_String));

      declare
         Empty_Index : constant Archive.Archives.Index.Archive_Index :=
           Archive.Archives.Index.Build (Physical).Index;
         Seed_Plan : constant Archive.Writes.Plans.Write_Plan :=
           Archive.Writes.Plans.Build (Empty_Index, Requests, Session => 17);
         Seed_Path : constant String := Root & "/seed.tar";
         Seed_Publish : constant Archive.Writes.Results.Publish_Result :=
           Archive.Writes.Execution.Publish_Tar (Seed_Path, Seed_Plan, Overwrite => True);
         Seed_Open : constant Archive.Archives.Readers.Dispatch.Open_Result :=
           Archive.Archives.Readers.Dispatch.Open_File (Seed_Path);
         A_Id : constant Archive.Types.Entry_Id := Entry_Id_For (Seed_Open.Index, "docs/a.txt");
         B_Id : constant Archive.Types.Entry_Id := Entry_Id_For (Seed_Open.Index, "docs/b.txt");
      begin
         Assert
           (Seed_Publish.Status = Archive.Writes.Results.Write_Completed
            and then Seed_Open.Status = Archive.Archives.Errors.Ok
            and then Archive.Archives.Index.Physical_Count (Seed_Open.Index) = 2,
            "tar mutation seed opens with two physical entries");

         Requests.Clear;
         Requests.Append
           (Archive.Writes.Plans.Write_Request'
              (Action           => Archive.Writes.Plans.Remove_Entry,
               Source_Entry     => A_Id,
               Host_Source      => Null_Unbounded_String,
               Target_Path      => Null_Unbounded_String,
               Replacement_Path => Null_Unbounded_String));
         declare
            Remove_Plan : constant Archive.Writes.Plans.Write_Plan :=
              Archive.Writes.Plans.Build (Seed_Open.Index, Requests, Session => 18);
            Removed_Path : constant String := Root & "/removed.tar";
            Removed_Tar : constant Archive.Writes.Results.Publish_Result :=
              Archive.Writes.Execution.Publish_Tar
                (Removed_Path, Remove_Plan, Source_Path => Seed_Path, Overwrite => True);
            Removed_Open : constant Archive.Archives.Readers.Dispatch.Open_Result :=
              Archive.Archives.Readers.Dispatch.Open_File (Removed_Path);
         begin
            Assert (Removed_Tar.Status = Archive.Writes.Results.Write_Completed,
                    "tar writer streams remove rewrite through tarlib");
            Assert
              (Removed_Open.Status = Archive.Archives.Errors.Ok
               and then Archive.Archives.Index.Physical_Count (Removed_Open.Index) = 1
               and then Entry_Id_For (Removed_Open.Index, "docs/a.txt") = Archive.Types.No_Entry
               and then Entry_Id_For (Removed_Open.Index, "docs/b.txt") /= Archive.Types.No_Entry,
               "tar remove rewrite drops only selected entry");
         end;

         Requests.Clear;
         Requests.Append
           (Archive.Writes.Plans.Write_Request'
              (Action           => Archive.Writes.Plans.Rename_Entry,
               Source_Entry     => B_Id,
               Host_Source      => Null_Unbounded_String,
               Target_Path      => Null_Unbounded_String,
               Replacement_Path => To_Unbounded_String ("docs/c.txt")));
         declare
            Rename_Plan : constant Archive.Writes.Plans.Write_Plan :=
              Archive.Writes.Plans.Build (Seed_Open.Index, Requests, Session => 19);
            Renamed_Path : constant String := Root & "/renamed.tar";
            Renamed_Tar : constant Archive.Writes.Results.Publish_Result :=
              Archive.Writes.Execution.Publish_Tar
                (Renamed_Path, Rename_Plan, Source_Path => Seed_Path, Overwrite => True);
            Renamed_Open : constant Archive.Archives.Readers.Dispatch.Open_Result :=
              Archive.Archives.Readers.Dispatch.Open_File (Renamed_Path);
         begin
            Assert (Renamed_Tar.Status = Archive.Writes.Results.Write_Completed,
                    "tar writer streams rename rewrite through tarlib");
            Assert
              (Renamed_Open.Status = Archive.Archives.Errors.Ok
               and then Archive.Archives.Index.Physical_Count (Renamed_Open.Index) = 2
               and then Entry_Id_For (Renamed_Open.Index, "docs/b.txt") = Archive.Types.No_Entry
               and then Entry_Id_For (Renamed_Open.Index, "docs/c.txt") /= Archive.Types.No_Entry,
               "tar rename rewrite preserves payload under replacement path");
         end;

         Requests.Clear;
         Requests.Append
           (Archive.Writes.Plans.Write_Request'
              (Action           => Archive.Writes.Plans.Replace_File,
               Source_Entry     => A_Id,
               Host_Source      => To_Unbounded_String (Host_File_2),
               Target_Path      => To_Unbounded_String ("docs/a.txt"),
               Replacement_Path => Null_Unbounded_String));
         declare
            Replace_Plan : constant Archive.Writes.Plans.Write_Plan :=
              Archive.Writes.Plans.Build (Seed_Open.Index, Requests, Session => 20);
            Replaced_Path : constant String := Root & "/replaced.tar";
            Replaced_Tar : constant Archive.Writes.Results.Publish_Result :=
              Archive.Writes.Execution.Publish_Tar
                (Replaced_Path, Replace_Plan, Source_Path => Seed_Path, Overwrite => True);
            Replaced_Open : constant Archive.Archives.Readers.Dispatch.Open_Result :=
              Archive.Archives.Readers.Dispatch.Open_File (Replaced_Path);
            Replaced_Id : constant Archive.Types.Entry_Id :=
              Entry_Id_For (Replaced_Open.Index, "docs/a.txt");
            Replaced_Payload : constant Test_Stream_Result :=
              Stream_Dispatch_Payload_File
                (Replaced_Path,
                 "replaced.tar",
                 Archive.Archives.Index.Entry_For (Replaced_Open.Index, Replaced_Id));
         begin
            Assert (Replaced_Tar.Status = Archive.Writes.Results.Write_Completed,
                    "tar writer streams replace rewrite through tarlib");
            Assert
              (Replaced_Open.Status = Archive.Archives.Errors.Ok
               and then Archive.Archives.Index.Physical_Count (Replaced_Open.Index) = 2
               and then Replaced_Payload.Status = Archive.Archives.Errors.Ok
               and then Replaced_Payload.Bytes_Written = 2
               and then Bytes_Of (Replaced_Payload) (1) = Zlib.Byte (Character'Pos ('n'))
               and then Bytes_Of (Replaced_Payload) (2) = Zlib.Byte (Character'Pos ('o')),
               "tar replace rewrite updates payload and preserves archive shape");
         end;
      end;

      Requests.Clear;
      Requests.Append
        (Archive.Writes.Plans.Write_Request'
           (Action           => Archive.Writes.Plans.Add_File,
            Source_Entry     => Archive.Types.No_Entry,
            Host_Source      => To_Unbounded_String (Host_File),
            Target_Path      => To_Unbounded_String ("docs/readme.txt"),
            Replacement_Path => Null_Unbounded_String));

      declare
         Tar_Path : constant String := Root & "/roundtrip.tar";
         Plan : constant Archive.Writes.Plans.Write_Plan :=
           Archive.Writes.Plans.Build
             (Archive.Archives.Index.Build (Physical).Index, Requests, Session => 8);
         Published : constant Archive.Writes.Results.Publish_Result :=
           Archive.Writes.Execution.Publish_Tar (Tar_Path, Plan, Overwrite => True);
      begin
         Assert (Published.Status = Archive.Writes.Results.Write_Completed,
                 "streaming tar publisher writes roundtrip archive");
         declare
            Parsed : constant Archive.Archives.Readers.Tar.Tar_Index_Result :=
              Archive.Archives.Readers.Tar.Index_File (Tar_Path);
         begin
            Assert (Parsed.Status = Archive.Archives.Errors.Ok,
                    "file-backed tar index uses tarlib file source");
            Assert (Natural (Parsed.Entries.Length) = 1,
                    "file-backed tar index retains physical entry");
            declare
               Readback : constant Test_Stream_Result :=
                 Stream_Tar_Payload_File (Tar_Path, Parsed.Entries.Element (1));
            begin
               Assert
                 (Readback.Status = Archive.Archives.Errors.Ok
                  and then Readback.Bytes_Written = 2
                  and then Bytes_Of (Readback) (1) = Zlib.Byte (Character'Pos ('o'))
                  and then Bytes_Of (Readback) (2) = Zlib.Byte (Character'Pos ('k')),
                  "file-backed tar payload reads through tarlib file source");
            end;
         end;
      end;

      declare
         Sink   : aliased Memory_Tar_Sink;
         Writer : Tarlib.Writers.Writer;
         Status : Tarlib.Errors.Status;
         Meta   : Tarlib.Entries.Metadata :=
           Tarlib.Entries.Default_Metadata (Tarlib.Entries.Regular_File);
         Data   : constant Ada.Streams.Stream_Element_Array :=
           [1 => Ada.Streams.Stream_Element (Character'Pos ('m'))];
      begin
         Tarlib.Entries.Set_Text (Meta.User_Name, "alice", Status);
         Assert (Status.Code = Tarlib.Errors.Success, "tar metadata fixture sets user name");
         Tarlib.Entries.Set_Text (Meta.Group_Name, "staff", Status);
         Assert (Status.Code = Tarlib.Errors.Success, "tar metadata fixture sets group name");
         Meta.Mode := 8#0640#;
         Meta.UID := 501;
         Meta.GID := 20;
         Meta.MTime := 1_234;
         Meta.ATime := 1_235;
         Meta.CTime := 1_236;

         Tarlib.Writers.Initialize (Writer, Sink, Status);
         Assert (Status.Code = Tarlib.Errors.Success, "tar metadata fixture writer initializes");
         Tarlib.Writers.Add_Extended_Record (Writer, "comment", "retained", Status);
         Assert (Status.Code = Tarlib.Errors.Success, "tar metadata fixture adds pax record");
         Tarlib.Writers.Begin_Entry
           (Writer, "meta.txt", Tarlib.Entries.Regular_File, Tarlib.Byte_Count (Data'Length),
            Meta, Status);
         Assert (Status.Code = Tarlib.Errors.Success, "tar metadata fixture begins file");
         Tarlib.Writers.Write (Writer, Data, Status);
         Assert (Status.Code = Tarlib.Errors.Success, "tar metadata fixture writes file");
         Tarlib.Writers.End_Entry (Writer, Status);
         Assert (Status.Code = Tarlib.Errors.Success, "tar metadata fixture ends file");
         Tarlib.Writers.Add_Symbolic_Link (Writer, "meta-link", "meta.txt", Status);
         Assert (Status.Code = Tarlib.Errors.Success, "tar metadata fixture adds link");
         Tarlib.Writers.Finish (Writer, Status);
         Assert (Status.Code = Tarlib.Errors.Success, "tar metadata fixture finishes archive");

         declare
            Bytes : Zlib.Byte_Array (1 .. Natural (Sink.Length));
         begin
            for Index in Bytes'Range loop
               Bytes (Index) :=
                 Zlib.Byte (Sink.Buffer (Ada.Streams.Stream_Element_Offset (Index)));
            end loop;

            declare
               Parsed : constant Archive.Archives.Readers.Tar.Tar_Index_Result :=
                 Index_Tar (Bytes);
               File_Item : constant Archive.Archives.Entries.Archive_Entry :=
                 Parsed.Entries.Element (1);
               Link_Item : constant Archive.Archives.Entries.Archive_Entry :=
                 Parsed.Entries.Element (2);
            begin
               Assert (Parsed.Status = Archive.Archives.Errors.Ok,
                       "tar metadata fixture reopens through tarlib reader");
               Assert (To_String (File_Item.Owner_Name) = "alice",
                       "tar adapter maps tarlib user name");
               Assert (To_String (File_Item.Group_Name) = "staff",
                       "tar adapter maps tarlib group name");
               Assert (To_String (File_Item.Permissions) = "416",
                       "tar adapter maps tarlib file mode");
               Assert (To_String (File_Item.Modified_Time) = "1234",
                       "tar adapter maps tarlib mtime");
               Assert
                 (Ada.Strings.Fixed.Index
                    (To_String (File_Item.Format_Metadata), "tar.uid=501") > 0
                  and then Ada.Strings.Fixed.Index
                    (To_String (File_Item.Format_Metadata), "tar.pax_unknown_records=1") > 0,
                  "tar adapter retains bounded tarlib metadata diagnostics");
               Assert (Link_Item.Kind = Archive.Archives.Entries.Symbolic_Link,
                       "tar adapter maps tarlib symbolic link kind");
               Assert (To_String (Link_Item.Link_Target) = "meta.txt",
                       "tar adapter maps tarlib link target");
            end;
         end;
      end;

      declare
         Sink   : aliased Memory_Tar_Sink;
         Writer : Tarlib.Writers.Writer;
         Status : Tarlib.Errors.Status;
         Device : constant Tarlib.Entries.Device_Numbers := (Major => 1, Minor => 5);
         Long_Path : constant String :=
           "long-path-components/segment-0000000001/segment-0000000002/"
           & "segment-0000000003/segment-0000000004/file.txt";
         Data : constant Ada.Streams.Stream_Element_Array :=
           [1 => Ada.Streams.Stream_Element (Character'Pos ('x'))];
      begin
         Tarlib.Writers.Initialize (Writer, Sink, Status);
         Assert (Status.Code = Tarlib.Errors.Success, "tar rich fixture writer initializes");
         Tarlib.Writers.Add_Directory (Writer, "dir", Status);
         Assert (Status.Code = Tarlib.Errors.Success, "tar rich fixture adds directory");
         Tarlib.Writers.Begin_File (Writer, "dup.txt", Tarlib.Byte_Count (Data'Length), Status);
         Assert (Status.Code = Tarlib.Errors.Success, "tar rich fixture begins first duplicate");
         Tarlib.Writers.Write (Writer, Data, Status);
         Assert (Status.Code = Tarlib.Errors.Success, "tar rich fixture writes first duplicate");
         Tarlib.Writers.End_Entry (Writer, Status);
         Assert (Status.Code = Tarlib.Errors.Success, "tar rich fixture ends first duplicate");
         Tarlib.Writers.Begin_File (Writer, "dup.txt", Tarlib.Byte_Count (Data'Length), Status);
         Assert (Status.Code = Tarlib.Errors.Success, "tar rich fixture begins second duplicate");
         Tarlib.Writers.Write (Writer, Data, Status);
         Assert (Status.Code = Tarlib.Errors.Success, "tar rich fixture writes second duplicate");
         Tarlib.Writers.End_Entry (Writer, Status);
         Assert (Status.Code = Tarlib.Errors.Success, "tar rich fixture ends second duplicate");
         Tarlib.Writers.Begin_File (Writer, Long_Path, Tarlib.Byte_Count (Data'Length), Status);
         Assert (Status.Code = Tarlib.Errors.Success, "tar rich fixture begins pax long path file");
         Tarlib.Writers.Write (Writer, Data, Status);
         Assert (Status.Code = Tarlib.Errors.Success, "tar rich fixture writes pax long path file");
         Tarlib.Writers.End_Entry (Writer, Status);
         Assert (Status.Code = Tarlib.Errors.Success, "tar rich fixture ends pax long path file");
         Tarlib.Writers.Add_Hard_Link (Writer, "hard", "dup.txt", Status);
         Assert (Status.Code = Tarlib.Errors.Success, "tar rich fixture adds hard link");
         Tarlib.Writers.Add_Character_Device (Writer, "tty", Device, Status);
         Assert (Status.Code = Tarlib.Errors.Success, "tar rich fixture adds character device");
         Tarlib.Writers.Add_Block_Device (Writer, "disk", Device, Status);
         Assert (Status.Code = Tarlib.Errors.Success, "tar rich fixture adds block device");
         Tarlib.Writers.Add_FIFO (Writer, "pipe", Status);
         Assert (Status.Code = Tarlib.Errors.Success, "tar rich fixture adds fifo");
         Tarlib.Writers.Finish (Writer, Status);
         Assert (Status.Code = Tarlib.Errors.Success, "tar rich fixture finishes archive");

         declare
            Bytes : constant Zlib.Byte_Array := Tar_Sink_Bytes (Sink);
            Parsed : constant Archive.Archives.Readers.Tar.Tar_Index_Result :=
              Index_Tar (Bytes);
         begin
            Assert (Parsed.Status = Archive.Archives.Errors.Ok,
                    "tar rich fixture reopens through tarlib reader");
            Assert (Natural (Parsed.Entries.Length) = 8,
                    "tar adapter retains physical rich fixture entries");
            Assert (Parsed.Entries.Element (1).Kind = Archive.Archives.Entries.Directory,
                    "tar adapter maps explicit directory kind");
            Assert
              (To_String (Parsed.Entries.Element (2).Original_Path) =
               To_String (Parsed.Entries.Element (3).Original_Path),
               "tar adapter preserves duplicate physical paths");
            Assert (To_String (Parsed.Entries.Element (4).Original_Path) = Long_Path,
                    "tar adapter maps tarlib pax long path");
            Assert (Parsed.Entries.Element (5).Kind = Archive.Archives.Entries.Hard_Link,
                    "tar adapter maps hard link kind");
            Assert (To_String (Parsed.Entries.Element (5).Link_Target) = "dup.txt",
                    "tar adapter maps hard link target");
            Assert (Parsed.Entries.Element (6).Kind = Archive.Archives.Entries.Character_Device,
                    "tar adapter maps character device kind");
            Assert
              (Ada.Strings.Fixed.Index
                 (To_String (Parsed.Entries.Element (6).Format_Metadata),
                  "tar.device_major=1") > 0
               and then Ada.Strings.Fixed.Index
                 (To_String (Parsed.Entries.Element (6).Format_Metadata),
                  "tar.device_minor=5") > 0,
               "tar adapter retains tarlib device metadata");
            Assert (Parsed.Entries.Element (7).Kind = Archive.Archives.Entries.Block_Device,
                    "tar adapter maps block device kind");
            Assert (Parsed.Entries.Element (8).Kind = Archive.Archives.Entries.FIFO,
                    "tar adapter maps fifo kind");
         end;
      end;

      declare
         Sink   : aliased Memory_Tar_Sink;
         Writer : Tarlib.Writers.Writer;
         Status : Tarlib.Errors.Status;
         Extents : constant Tarlib.Entries.Sparse_Extent_Array :=
           [1 => (Offset => 0, Length => 1),
            2 => (Offset => 3, Length => 1)];
         Physical_Data : constant Ada.Streams.Stream_Element_Array :=
           [1 => Ada.Streams.Stream_Element (Character'Pos ('A')),
            2 => Ada.Streams.Stream_Element (Character'Pos ('B'))];
      begin
         Tarlib.Writers.Initialize (Writer, Sink, Status);
         Assert (Status.Code = Tarlib.Errors.Success, "tar sparse fixture writer initializes");
         Tarlib.Writers.Begin_Sparse_File
           (Writer, "sparse.bin", 5, Extents, Status);
         Assert (Status.Code = Tarlib.Errors.Success, "tar sparse fixture begins file");
         Tarlib.Writers.Write (Writer, Physical_Data, Status);
         Assert (Status.Code = Tarlib.Errors.Success, "tar sparse fixture writes physical extents");
         Tarlib.Writers.End_Entry (Writer, Status);
         Assert (Status.Code = Tarlib.Errors.Success, "tar sparse fixture ends file");
         Tarlib.Writers.Finish (Writer, Status);
         Assert (Status.Code = Tarlib.Errors.Success, "tar sparse fixture finishes archive");

         declare
            Bytes : constant Zlib.Byte_Array := Tar_Sink_Bytes (Sink);
            Parsed : constant Archive.Archives.Readers.Tar.Tar_Index_Result :=
              Index_Tar (Bytes);
         begin
            Assert (Parsed.Status = Archive.Archives.Errors.Ok,
                    "tar sparse fixture reopens through tarlib reader");
            Assert (Natural (Parsed.Entries.Length) = 1,
                    "tar sparse fixture retains one logical entry");

            declare
               Item : constant Archive.Archives.Entries.Archive_Entry :=
                 Parsed.Entries.Element (1);
               Readback : constant Test_Stream_Result :=
                 Stream_Tar_Payload (Bytes, Item);
            begin
               Assert (Item.Kind = Archive.Archives.Entries.Regular_File,
                       "tar sparse fixture maps to regular file");
               Assert
                 (Item.Compressed.Present
                  and then Item.Compressed.Value = 2
                  and then Item.Uncompressed.Present
                  and then Item.Uncompressed.Value = 5,
                  "tar sparse fixture records physical and logical sizes");
               Assert
                 (Ada.Strings.Fixed.Index
                    (To_String (Item.Format_Metadata), "tar.sparse_extents=2") > 0
                  and then Ada.Strings.Fixed.Index
                    (To_String (Item.Format_Metadata), "tar.sparse_first_offset=0") > 0
                  and then Ada.Strings.Fixed.Index
                    (To_String (Item.Format_Metadata), "tar.sparse_first_length=1") > 0,
                  "tar adapter retains sparse metadata exposed by tarlib");
               Assert
                 (Readback.Status = Archive.Archives.Errors.Ok
                  and then Readback.Bytes_Written = 5
                  and then Bytes_Of (Readback) (1) = Zlib.Byte (Character'Pos ('A'))
                  and then Bytes_Of (Readback) (2) = 0
                  and then Bytes_Of (Readback) (3) = 0
                  and then Bytes_Of (Readback) (4) = Zlib.Byte (Character'Pos ('B'))
                  and then Bytes_Of (Readback) (5) = 0,
                  "tar sparse payload reconstructs holes through tarlib reader");
            end;
         end;
      end;

      declare
         Bad_Checksum : Zlib.Byte_Array := One_File_Tar;
         Parsed : Archive.Archives.Readers.Tar.Tar_Index_Result;
      begin
         Bad_Checksum (Bad_Checksum'First) := Zlib.Byte (Character'Pos ('x'));
         Parsed := Index_Tar (Bad_Checksum);
         Assert (Parsed.Status = Archive.Archives.Errors.Invalid_Format,
                 "tar invalid checksum is rejected through tarlib");
      end;

      declare
         Full : constant Zlib.Byte_Array := One_File_Tar;
         Truncated : Zlib.Byte_Array (Full'First .. Full'First + 600);
         Parsed : Archive.Archives.Readers.Tar.Tar_Index_Result;
      begin
         for Index in Truncated'Range loop
            Truncated (Index) := Full (Index);
         end loop;
         Parsed := Index_Tar (Truncated);
         Assert (Parsed.Status = Archive.Archives.Errors.Invalid_Format,
                 "tar truncation is rejected through tarlib");
      end;
   end Test_Tar_Write_Adapter;

   procedure Test_Gzip_Write_Adapters (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      Plain : constant Zlib.Byte_Array :=
        [1 => Zlib.Byte (Character'Pos ('o')),
         2 => Zlib.Byte (Character'Pos ('k'))];
      Root : constant String := "obj/tar-gzip-write-adapter-test";
      Host_File : constant String := Root & "/input.txt";
      File : Ada.Streams.Stream_IO.File_Type;
      Host_Data : constant Ada.Streams.Stream_Element_Array :=
        [1 => Ada.Streams.Stream_Element (Character'Pos ('o')),
         2 => Ada.Streams.Stream_Element (Character'Pos ('k'))];
      Physical : Archive.Archives.Entries.Entry_Vectors.Vector;
      Requests : Archive.Writes.Plans.Write_Request_Vectors.Vector;

      function Entry_Id_For
        (Index : Archive.Archives.Index.Archive_Index;
         Path  : String)
         return Archive.Types.Entry_Id
      is
      begin
         for Raw_Id in 1 .. Archive.Archives.Index.Entry_Count (Index) loop
            declare
               Id   : constant Archive.Types.Entry_Id := Archive.Types.Entry_Id (Raw_Id);
               Item : constant Archive.Archives.Entries.Archive_Entry :=
                 Archive.Archives.Index.Entry_For (Index, Id);
            begin
               if To_String (Item.Original_Path) = Path then
                  return Id;
               end if;
            end;
         end loop;
         return Archive.Types.No_Entry;
      end Entry_Id_For;
   begin
      declare
         Gzip_Status : Zlib.Status_Code;
         Gzip : constant Zlib.Byte_Array := Zlib.GZip (Plain, Zlib.Fixed, Gzip_Status);
         Parsed : constant Archive.Archives.Readers.Gzip.Gzip_Index_Result :=
           Index_Gzip (Gzip, Source_Name => "payload.gz");
         Payload : constant Test_Stream_Result :=
           Stream_Gzip_Payload (Gzip, Parsed.Item);
      begin
         Assert (Gzip_Status = Zlib.Ok, "gzip payload builds through zlib");
         Assert (Parsed.Status = Archive.Archives.Errors.Ok, "gzip writer output indexes");
         Assert
           (Payload.Status = Archive.Archives.Errors.Ok
            and then Payload.Bytes_Written = 2
            and then Bytes_Of (Payload) (1) = Zlib.Byte (Character'Pos ('o'))
            and then Bytes_Of (Payload) (2) = Zlib.Byte (Character'Pos ('k')),
            "gzip writer payload round-trips");
      end;

      if not Ada.Directories.Exists (Root) then
         Ada.Directories.Create_Path (Root);
      end if;

      Ada.Streams.Stream_IO.Create (File, Ada.Streams.Stream_IO.Out_File, Host_File);
      Ada.Streams.Stream_IO.Write (File, Host_Data);
      Ada.Streams.Stream_IO.Close (File);

      declare
         Seed_Status : Zlib.Status_Code;
         Seed_Gzip : constant Zlib.Byte_Array := Zlib.GZip (Plain, Zlib.Fixed, Seed_Status);
         Seed_Path : constant String := Root & "/payload.txt.gz";
         Target_Path : constant String := Root & "/payload-updated.txt.gz";
      begin
         Assert (Seed_Status = Zlib.Ok, "standalone gzip seed builds through zlib");
         Write_Bytes (Seed_Path, Seed_Gzip);

         declare
            Seed_Open : constant Archive.Archives.Readers.Dispatch.Open_Result :=
              Archive.Archives.Readers.Dispatch.Open_File
                (Seed_Path, Source_Name => "payload.txt.gz");
            Source_Id : constant Archive.Types.Entry_Id :=
              Entry_Id_For (Seed_Open.Index, "payload.txt");
         begin
            Assert
              (Seed_Open.Status = Archive.Archives.Errors.Ok
               and then Seed_Open.Format = Archive.Archives.Formats.GZip_Format,
               "standalone gzip seed opens through dispatch");
            Assert (Source_Id /= Archive.Types.No_Entry,
                    "standalone gzip seed exposes logical file entry");

            Requests.Clear;
            Requests.Append
              (Archive.Writes.Plans.Write_Request'
                 (Action           => Archive.Writes.Plans.Replace_File,
                  Source_Entry     => Source_Id,
                  Host_Source      => To_Unbounded_String (Host_File),
                  Target_Path      => To_Unbounded_String ("payload.txt"),
                  Replacement_Path => Null_Unbounded_String));

            declare
               Plan : constant Archive.Writes.Plans.Write_Plan :=
                 Archive.Writes.Plans.Build (Seed_Open.Index, Requests, Session => 10);
               Published : constant Archive.Writes.Results.Publish_Result :=
                 Archive.Writes.Dispatch.Publish
                   (Archive.Archives.Formats.GZip_Format,
                    Target_Path,
                    Plan,
                    Overwrite => True);
               Reopened : constant Archive.Archives.Readers.Dispatch.Open_Result :=
                 Archive.Archives.Readers.Dispatch.Open_File
                   (Target_Path, Source_Name => "payload-updated.txt.gz");
               Reopened_Id : constant Archive.Types.Entry_Id :=
                 Entry_Id_For (Reopened.Index, "payload-updated.txt");
               Payload : constant Test_Stream_Result :=
                 Stream_Dispatch_Payload_File
                   (Target_Path,
                    Target_Path,
                    Archive.Archives.Index.Entry_For (Reopened.Index, Reopened_Id));
            begin
               Assert
                 (Plan.Status = Archive.Writes.Plans.Write_Plan_Ready,
                  "standalone gzip replacement plan is ready");
               Assert
                 (Published.Status = Archive.Writes.Results.Write_Completed,
                  "standalone gzip dispatch publishes replacement payload");
               Assert
                 (Reopened.Status = Archive.Archives.Errors.Ok
                  and then Reopened.Format = Archive.Archives.Formats.GZip_Format
                  and then Archive.Archives.Index.Physical_Count (Reopened.Index) = 1,
                  "standalone gzip dispatch output reopens as one logical archive entry");
               Assert
                 (Payload.Status = Archive.Archives.Errors.Ok
                  and then Payload.Integrity = Archive.Archives.Entries.Verified
                  and then Payload.Bytes_Written = 2
                  and then Bytes_Of (Payload) (1) = Zlib.Byte (Character'Pos ('o'))
                  and then Bytes_Of (Payload) (2) = Zlib.Byte (Character'Pos ('k')),
                  "standalone gzip dispatch replacement streams verified payload");
            end;
         end;
      end;

      Requests.Clear;
      Requests.Append
        (Archive.Writes.Plans.Write_Request'
           (Action           => Archive.Writes.Plans.Add_File,
            Source_Entry     => Archive.Types.No_Entry,
            Host_Source      => To_Unbounded_String (Host_File),
            Target_Path      => To_Unbounded_String ("docs/readme.txt"),
            Replacement_Path => Null_Unbounded_String));

      declare
         Index : constant Archive.Archives.Index.Archive_Index :=
           Archive.Archives.Index.Build (Physical).Index;
         Plan : constant Archive.Writes.Plans.Write_Plan :=
           Archive.Writes.Plans.Build (Index, Requests, Session => 7);
         Tar_Gz_Path : constant String := Root & "/writer.tar.gz";
         Published : constant Archive.Writes.Results.Publish_Result :=
           Archive.Writes.Execution.Publish_Tar_Gzip (Tar_Gz_Path, Plan, Overwrite => True);
         Opened : constant Archive.Archives.Readers.Dispatch.Open_Result :=
           Archive.Archives.Readers.Dispatch.Open_File
             (Tar_Gz_Path, Source_Name => Tar_Gz_Path, Retain_Backing => True);
      begin
         Assert (Published.Status = Archive.Writes.Results.Write_Completed,
                 "tar.gz writer streams payload");
         Assert (Opened.Status = Archive.Archives.Errors.Ok, "written tar.gz opens through dispatch");
         Assert (Opened.Format = Archive.Archives.Formats.Tar_GZip_Format, "written tar.gz format recorded");
         Assert (Archive.Archives.Index.Physical_Count (Opened.Index) = 1,
                 "written tar.gz contains one physical entry");
      end;

      if Ada.Directories.Exists (Root & "/stored-file-backed.zip") then
         Ada.Directories.Delete_File (Root & "/stored-file-backed.zip");
      end if;

      declare
         Index : constant Archive.Archives.Index.Archive_Index :=
           Archive.Archives.Index.Build (Physical).Index;
         Seed_Plan : constant Archive.Writes.Plans.Write_Plan :=
           Archive.Writes.Plans.Build (Index, Requests, Session => 8);
         Seed_Tar_Gz_Path : constant String := Root & "/seed.tar.gz";
         Seed_Published : constant Archive.Writes.Results.Publish_Result :=
           Archive.Writes.Execution.Publish_Tar_Gzip
             (Seed_Tar_Gz_Path, Seed_Plan, Overwrite => True);
         Seed_Open : constant Archive.Archives.Readers.Dispatch.Open_Result :=
           Archive.Archives.Readers.Dispatch.Open_File
             (Seed_Tar_Gz_Path, Source_Name => Seed_Tar_Gz_Path, Retain_Backing => True);
         Source_Id : constant Archive.Types.Entry_Id :=
           Entry_Id_For (Seed_Open.Index, "docs/readme.txt");
      begin
         Assert (Seed_Published.Status = Archive.Writes.Results.Write_Completed,
                 "tar.gz seed publishes through streaming writer");
         Requests.Clear;
         Requests.Append
           (Archive.Writes.Plans.Write_Request'
              (Action           => Archive.Writes.Plans.Rename_Entry,
               Source_Entry     => Source_Id,
               Host_Source      => Null_Unbounded_String,
               Target_Path      => Null_Unbounded_String,
               Replacement_Path => To_Unbounded_String ("docs/renamed.txt")));
         declare
            Rename_Plan : constant Archive.Writes.Plans.Write_Plan :=
              Archive.Writes.Plans.Build (Seed_Open.Index, Requests, Session => 9);
            Rewritten_Path : constant String := Root & "/rewritten.tar.gz";
            Rewritten : constant Archive.Writes.Results.Publish_Result :=
              Archive.Writes.Dispatch.Publish
                (Archive.Archives.Formats.Tar_GZip_Format,
                 Rewritten_Path,
                 Rename_Plan,
                 Source_Path => Seed_Tar_Gz_Path,
                 Overwrite => True);
            Reopened : constant Archive.Archives.Readers.Dispatch.Open_Result :=
              Archive.Archives.Readers.Dispatch.Open_File
                (Rewritten_Path, Source_Name => Rewritten_Path, Retain_Backing => True);
         begin
            Assert (Rewritten.Status = Archive.Writes.Results.Write_Completed,
                    "tar.gz dispatch rewrites compressed source through streaming zlib and tarlib");
            Assert
              (Reopened.Status = Archive.Archives.Errors.Ok
               and then Reopened.Format = Archive.Archives.Formats.Tar_GZip_Format
               and then Entry_Id_For (Reopened.Index, "docs/readme.txt") = Archive.Types.No_Entry
               and then Entry_Id_For (Reopened.Index, "docs/renamed.txt") /= Archive.Types.No_Entry,
               "tar.gz rewrite publishes renamed entry in reopened archive");
         end;
      end;
   end Test_Gzip_Write_Adapters;

   procedure Test_Zip_Write_Adapter (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      Root : constant String := "obj/zip-write-adapter-test";
      Host_File : constant String := Root & "/input.txt";
      Host_File_2 : constant String := Root & "/input-2.txt";
      File : Ada.Streams.Stream_IO.File_Type;
      Host_Data : constant Ada.Streams.Stream_Element_Array :=
        [1 => Ada.Streams.Stream_Element (Character'Pos ('o')),
         2 => Ada.Streams.Stream_Element (Character'Pos ('k'))];
      Host_Data_2 : constant Ada.Streams.Stream_Element_Array :=
        [1 => Ada.Streams.Stream_Element (Character'Pos ('g')),
         2 => Ada.Streams.Stream_Element (Character'Pos ('o'))];
      Physical : Archive.Archives.Entries.Entry_Vectors.Vector;
      Requests : Archive.Writes.Plans.Write_Request_Vectors.Vector;

      function Entry_Id_For
        (Index : Archive.Archives.Index.Archive_Index;
         Path  : String)
         return Archive.Types.Entry_Id
      is
      begin
         for Raw_Id in 1 .. Archive.Archives.Index.Entry_Count (Index) loop
            declare
               Id   : constant Archive.Types.Entry_Id := Archive.Types.Entry_Id (Raw_Id);
               Item : constant Archive.Archives.Entries.Archive_Entry :=
                 Archive.Archives.Index.Entry_For (Index, Id);
            begin
               if To_String (Item.Original_Path) = Path then
                  return Id;
               end if;
            end;
         end loop;
         return Archive.Types.No_Entry;
      end Entry_Id_For;
   begin
      if not Ada.Directories.Exists (Root) then
         Ada.Directories.Create_Path (Root);
      end if;

      Ada.Streams.Stream_IO.Create (File, Ada.Streams.Stream_IO.Out_File, Host_File);
      Ada.Streams.Stream_IO.Write (File, Host_Data);
      Ada.Streams.Stream_IO.Close (File);
      Ada.Streams.Stream_IO.Create (File, Ada.Streams.Stream_IO.Out_File, Host_File_2);
      Ada.Streams.Stream_IO.Write (File, Host_Data_2);
      Ada.Streams.Stream_IO.Close (File);

      Requests.Append
        (Archive.Writes.Plans.Write_Request'
           (Action           => Archive.Writes.Plans.Add_File,
            Source_Entry     => Archive.Types.No_Entry,
            Host_Source      => To_Unbounded_String (Host_File),
            Target_Path      => To_Unbounded_String ("docs/readme.txt"),
            Replacement_Path => Null_Unbounded_String));

      declare
         Index : constant Archive.Archives.Index.Archive_Index :=
           Archive.Archives.Index.Build (Physical).Index;
         Plan : constant Archive.Writes.Plans.Write_Plan :=
           Archive.Writes.Plans.Build (Index, Requests, Session => 7);
         Zip_Path : constant String := Root & "/stored-payload-free.zip";
         Zip : constant Archive.Writes.Results.Publish_Result :=
           Archive.Writes.Execution.Publish_Zip_Stored (Zip_Path, Plan, Overwrite => True);
         Parsed : constant Archive.Archives.Readers.Dispatch.Open_Result :=
           Archive.Archives.Readers.Dispatch.Open_File (Zip_Path);
         Item_Id : constant Archive.Types.Entry_Id :=
           Entry_Id_For (Parsed.Index, "docs/readme.txt");
         Payload : constant Test_Stream_Result :=
           Stream_Zip_Payload_File
             (Zip_Path, Archive.Archives.Index.Entry_For (Parsed.Index, Item_Id));
      begin
         Assert (Zip.Status = Archive.Writes.Results.Write_Completed,
                 "stored zip writer streams payload");
         Assert (Parsed.Status = Archive.Archives.Errors.Ok, "written zip indexes");
         Assert (Archive.Archives.Index.Physical_Count (Parsed.Index) = 1,
                 "written zip contains one physical entry");
         Assert
           (Payload.Status = Archive.Archives.Errors.Ok
            and then Payload.Integrity = Archive.Archives.Entries.Verified
            and then Payload.Bytes_Written = 2
            and then Bytes_Of (Payload) (1) = Zlib.Byte (Character'Pos ('o'))
            and then Bytes_Of (Payload) (2) = Zlib.Byte (Character'Pos ('k')),
            "stored zip payload round-trips with crc verification");
      end;

      if Ada.Directories.Exists (Root & "/stored-file-backed.zip") then
         Ada.Directories.Delete_File (Root & "/stored-file-backed.zip");
      end if;

      declare
         Index : constant Archive.Archives.Index.Archive_Index :=
           Archive.Archives.Index.Build (Physical).Index;
         Plan : constant Archive.Writes.Plans.Write_Plan :=
           Archive.Writes.Plans.Build (Index, Requests, Session => 7);
         File_Zip_Path : constant String := Root & "/stored-file-backed.zip";
         Published : constant Archive.Writes.Results.Publish_Result :=
           Archive.Writes.Execution.Publish_Zip_Stored (File_Zip_Path, Plan);
         File_Opened : constant Archive.Archives.Readers.Dispatch.Open_Result :=
           Archive.Archives.Readers.Dispatch.Open_File (File_Zip_Path);
      begin
         Assert (Published.Status = Archive.Writes.Results.Write_Completed,
                 "file-backed stored zip publisher completes");
         Assert (File_Opened.Status = Archive.Archives.Errors.Ok,
                 "file-backed stored zip publisher output opens from disk");
         declare
            File_Payload : constant Test_Stream_Result :=
              Stream_Dispatch_Payload_File
                (File_Zip_Path, "stored-file-backed.zip",
                 Archive.Archives.Index.Entry_For
                   (File_Opened.Index, Entry_Id_For (File_Opened.Index, "docs/readme.txt")));
         begin
            Assert
              (File_Payload.Status = Archive.Archives.Errors.Ok
               and then File_Payload.Integrity = Archive.Archives.Entries.Verified
               and then File_Payload.Bytes_Written = 2
               and then Bytes_Of (File_Payload) (1) = Zlib.Byte (Character'Pos ('o'))
               and then Bytes_Of (File_Payload) (2) = Zlib.Byte (Character'Pos ('k')),
               "file-backed stored zip publisher streams file payload with crc");
         end;
      end;

      if Ada.Directories.Exists (Root & "/deflate-file-backed.zip") then
         Ada.Directories.Delete_File (Root & "/deflate-file-backed.zip");
      end if;

      declare
         Index : constant Archive.Archives.Index.Archive_Index :=
           Archive.Archives.Index.Build (Physical).Index;
         Plan : constant Archive.Writes.Plans.Write_Plan :=
           Archive.Writes.Plans.Build (Index, Requests, Session => 8);
         File_Zip_Path : constant String := Root & "/deflate-file-backed.zip";
         Published : constant Archive.Writes.Results.Publish_Result :=
           Archive.Writes.Execution.Publish_Zip_Deflate (File_Zip_Path, Plan);
         File_Opened : constant Archive.Archives.Readers.Dispatch.Open_Result :=
           Archive.Archives.Readers.Dispatch.Open_File (File_Zip_Path);
      begin
         Assert (Published.Status = Archive.Writes.Results.Write_Completed,
                 "file-backed deflate zip publisher completes");
         Assert
           (File_Opened.Status = Archive.Archives.Errors.Ok
            and then Archive.Archives.Index.Entry_For
              (File_Opened.Index, Entry_Id_For (File_Opened.Index, "docs/readme.txt")).Method =
                Archive.Archives.Entries.Zip_Deflate,
            "file-backed deflate zip publisher records method 8");
         declare
            File_Payload : constant Test_Stream_Result :=
              Stream_Dispatch_Payload_File
                (File_Zip_Path, "deflate-file-backed.zip",
                 Archive.Archives.Index.Entry_For
                   (File_Opened.Index, Entry_Id_For (File_Opened.Index, "docs/readme.txt")));
         begin
            Assert
              (File_Payload.Status = Archive.Archives.Errors.Ok
               and then File_Payload.Integrity = Archive.Archives.Entries.Verified
               and then File_Payload.Bytes_Written = 2
               and then Bytes_Of (File_Payload) (1) = Zlib.Byte (Character'Pos ('o'))
               and then Bytes_Of (File_Payload) (2) = Zlib.Byte (Character'Pos ('k')),
               "file-backed deflate zip publisher streams compressed payload with crc");
         end;
      end;

      declare
         Index : constant Archive.Archives.Index.Archive_Index :=
           Archive.Archives.Index.Build (Physical).Index;
         Plan : constant Archive.Writes.Plans.Write_Plan :=
           Archive.Writes.Plans.Build (Index, Requests, Session => 7);
         Zip_Path : constant String := Root & "/deflate-payload-free.zip";
         Zip : constant Archive.Writes.Results.Publish_Result :=
           Archive.Writes.Execution.Publish_Zip_Deflate (Zip_Path, Plan, Overwrite => True);
         Parsed : constant Archive.Archives.Readers.Dispatch.Open_Result :=
           Archive.Archives.Readers.Dispatch.Open_File (Zip_Path);
         Item_Id : constant Archive.Types.Entry_Id :=
           Entry_Id_For (Parsed.Index, "docs/readme.txt");
         Payload : constant Test_Stream_Result :=
           Stream_Zip_Payload_File
             (Zip_Path, Archive.Archives.Index.Entry_For (Parsed.Index, Item_Id));
      begin
         Assert (Zip.Status = Archive.Writes.Results.Write_Completed,
                 "deflate zip writer streams payload");
         Assert (Parsed.Status = Archive.Archives.Errors.Ok, "written deflate zip indexes");
         Assert (Archive.Archives.Index.Entry_For (Parsed.Index, Item_Id).Method =
                   Archive.Archives.Entries.Zip_Deflate,
                 "written deflate zip records method 8");
         Assert
           (Payload.Status = Archive.Archives.Errors.Ok
            and then Payload.Integrity = Archive.Archives.Entries.Verified
            and then Payload.Bytes_Written = 2
            and then Bytes_Of (Payload) (1) = Zlib.Byte (Character'Pos ('o'))
            and then Bytes_Of (Payload) (2) = Zlib.Byte (Character'Pos ('k')),
            "deflate zip payload round-trips with crc verification");
      end;

      Requests.Clear;
      Requests.Append
        (Archive.Writes.Plans.Write_Request'
           (Action           => Archive.Writes.Plans.Add_Directory,
            Source_Entry     => Archive.Types.No_Entry,
            Host_Source      => To_Unbounded_String (Root & "/docs"),
            Target_Path      => To_Unbounded_String ("docs"),
            Replacement_Path => Null_Unbounded_String));

      declare
         Index : constant Archive.Archives.Index.Archive_Index :=
           Archive.Archives.Index.Build (Physical).Index;
         Plan : constant Archive.Writes.Plans.Write_Plan :=
           Archive.Writes.Plans.Build (Index, Requests, Session => 7);
         Zip_Path : constant String := Root & "/directory-payload-free.zip";
         Zip : constant Archive.Writes.Results.Publish_Result :=
           Archive.Writes.Execution.Publish_Zip_Stored (Zip_Path, Plan, Overwrite => True);
         Parsed : constant Archive.Archives.Readers.Dispatch.Open_Result :=
           Archive.Archives.Readers.Dispatch.Open_File (Zip_Path);
         Item_Id : constant Archive.Types.Entry_Id :=
           Entry_Id_For (Parsed.Index, "docs/");
      begin
         Assert (Zip.Status = Archive.Writes.Results.Write_Completed,
                 "zip writer streams explicit directory payload");
         Assert (Parsed.Status = Archive.Archives.Errors.Ok,
                 "written directory zip indexes");
         Assert (Archive.Archives.Index.Physical_Count (Parsed.Index) = 1,
                 "written directory zip contains one physical entry");
         Assert
           (Archive.Archives.Index.Entry_For (Parsed.Index, Item_Id).Kind =
              Archive.Archives.Entries.Directory
            and then To_String
              (Archive.Archives.Index.Entry_For (Parsed.Index, Item_Id).Original_Path) = "docs/",
            "written directory is represented as an explicit directory entry");
      end;

      Requests.Clear;
      Requests.Append
        (Archive.Writes.Plans.Write_Request'
           (Action           => Archive.Writes.Plans.Add_File,
            Source_Entry     => Archive.Types.No_Entry,
            Host_Source      => To_Unbounded_String (Host_File),
            Target_Path      => To_Unbounded_String ("docs/a.txt"),
            Replacement_Path => Null_Unbounded_String));
      Requests.Append
        (Archive.Writes.Plans.Write_Request'
           (Action           => Archive.Writes.Plans.Add_File,
            Source_Entry     => Archive.Types.No_Entry,
            Host_Source      => To_Unbounded_String (Host_File_2),
            Target_Path      => To_Unbounded_String ("docs/b.txt"),
            Replacement_Path => Null_Unbounded_String));

      declare
         Empty_Index : constant Archive.Archives.Index.Archive_Index :=
           Archive.Archives.Index.Build (Physical).Index;
         Seed_Plan : constant Archive.Writes.Plans.Write_Plan :=
           Archive.Writes.Plans.Build (Empty_Index, Requests, Session => 7);
         Seed_Path : constant String := Root & "/seed.zip";
         Seed_Zip : constant Archive.Writes.Results.Publish_Result :=
           Archive.Writes.Execution.Publish_Zip_Stored
             (Seed_Path, Seed_Plan, Overwrite => True);
         Seed_Open : constant Archive.Archives.Readers.Dispatch.Open_Result :=
           Archive.Archives.Readers.Dispatch.Open_File (Seed_Path);
         A_Id : constant Archive.Types.Entry_Id := Entry_Id_For (Seed_Open.Index, "docs/a.txt");
         B_Id : constant Archive.Types.Entry_Id := Entry_Id_For (Seed_Open.Index, "docs/b.txt");
      begin
         Assert (Seed_Zip.Status = Archive.Writes.Results.Write_Completed
                 and then Seed_Open.Status = Archive.Archives.Errors.Ok
                 and then Archive.Archives.Index.Physical_Count (Seed_Open.Index) = 2,
                 "source-aware zip rewrite test starts from two physical entries");

         Requests.Clear;
         Requests.Append
           (Archive.Writes.Plans.Write_Request'
              (Action           => Archive.Writes.Plans.Remove_Entry,
               Source_Entry     => A_Id,
               Host_Source      => Null_Unbounded_String,
               Target_Path      => Null_Unbounded_String,
               Replacement_Path => Null_Unbounded_String));
         declare
            Remove_Plan : constant Archive.Writes.Plans.Write_Plan :=
              Archive.Writes.Plans.Build (Seed_Open.Index, Requests, Session => 8);
            Removed_Path : constant String := Root & "/removed.zip";
            Removed_Zip : constant Archive.Writes.Results.Publish_Result :=
              Archive.Writes.Execution.Publish_Zip_Stored
                (Removed_Path, Remove_Plan,
                 Source_Path => Seed_Path,
                 Source_Name => Seed_Path,
                 Overwrite => True);
            Removed_Open : constant Archive.Archives.Readers.Dispatch.Open_Result :=
              Archive.Archives.Readers.Dispatch.Open_File (Removed_Path);
         begin
            Assert (Removed_Zip.Status = Archive.Writes.Results.Write_Completed,
                    "zip writer streams remove rewrite payload");
            Assert
              (Removed_Open.Status = Archive.Archives.Errors.Ok
               and then Archive.Archives.Index.Physical_Count (Removed_Open.Index) = 1
               and then Entry_Id_For (Removed_Open.Index, "docs/a.txt") = Archive.Types.No_Entry
               and then Entry_Id_For (Removed_Open.Index, "docs/b.txt") /= Archive.Types.No_Entry,
               "zip remove rewrite drops only the selected entry");
         end;

         Requests.Clear;
         Requests.Append
           (Archive.Writes.Plans.Write_Request'
              (Action           => Archive.Writes.Plans.Rename_Entry,
               Source_Entry     => B_Id,
               Host_Source      => Null_Unbounded_String,
               Target_Path      => Null_Unbounded_String,
               Replacement_Path => To_Unbounded_String ("docs/c.txt")));
         declare
            Rename_Plan : constant Archive.Writes.Plans.Write_Plan :=
              Archive.Writes.Plans.Build (Seed_Open.Index, Requests, Session => 9);
            Renamed_Path : constant String := Root & "/renamed.zip";
            Renamed_Zip : constant Archive.Writes.Results.Publish_Result :=
              Archive.Writes.Execution.Publish_Zip_Stored
                (Renamed_Path, Rename_Plan,
                 Source_Path => Seed_Path,
                 Source_Name => Seed_Path,
                 Overwrite => True);
            Renamed_Open : constant Archive.Archives.Readers.Dispatch.Open_Result :=
              Archive.Archives.Readers.Dispatch.Open_File (Renamed_Path);
         begin
            Assert (Renamed_Zip.Status = Archive.Writes.Results.Write_Completed,
                    "zip writer streams rename rewrite payload");
            Assert
              (Renamed_Open.Status = Archive.Archives.Errors.Ok
               and then Archive.Archives.Index.Physical_Count (Renamed_Open.Index) = 2
               and then Entry_Id_For (Renamed_Open.Index, "docs/b.txt") = Archive.Types.No_Entry
               and then Entry_Id_For (Renamed_Open.Index, "docs/c.txt") /= Archive.Types.No_Entry,
               "zip rename rewrite preserves payload under replacement path");
         end;

         declare
            Rename_Plan : constant Archive.Writes.Plans.Write_Plan :=
              Archive.Writes.Plans.Build (Seed_Open.Index, Requests, Session => 11);
            Recompressed_Path : constant String := Root & "/renamed-bzip2.zip";
            Recompressed_Zip : constant Archive.Writes.Results.Publish_Result :=
              Archive.Writes.Execution.Publish_Zip_BZip2
                (Recompressed_Path,
                 Rename_Plan,
                 Source_Path => Seed_Path,
                 Source_Name => Seed_Path,
                 Overwrite => True);
            Recompressed_Open : constant Archive.Archives.Readers.Dispatch.Open_Result :=
              Archive.Archives.Readers.Dispatch.Open_File (Recompressed_Path);
            Recompressed_Id : constant Archive.Types.Entry_Id :=
              Entry_Id_For (Recompressed_Open.Index, "docs/c.txt");
            Recompressed_Item : constant Archive.Archives.Entries.Archive_Entry :=
              Archive.Archives.Index.Entry_For
                (Recompressed_Open.Index, Recompressed_Id);
            Recompressed_Payload : constant Test_Stream_Result :=
              Stream_Dispatch_Payload_File
                (Recompressed_Path, "renamed-bzip2.zip", Recompressed_Item);
         begin
            Assert (Recompressed_Zip.Status = Archive.Writes.Results.Write_Completed,
                    "zip external writer recompresses renamed source payload");
            Assert
              (Recompressed_Open.Status = Archive.Archives.Errors.Ok
               and then Recompressed_Item.Method =
                 Archive.Archives.Entries.BZip2_Compression
               and then Recompressed_Payload.Status = Archive.Archives.Errors.Ok
               and then Recompressed_Payload.Bytes_Written = 2
               and then Bytes_Of (Recompressed_Payload) (1) =
                 Zlib.Byte (Character'Pos ('g'))
               and then Bytes_Of (Recompressed_Payload) (2) =
                 Zlib.Byte (Character'Pos ('o')),
               "zip external rewrite preserves payload under renamed bzip2 entry");
         end;

         Requests.Clear;
         Requests.Append
           (Archive.Writes.Plans.Write_Request'
              (Action           => Archive.Writes.Plans.Replace_File,
               Source_Entry     => A_Id,
               Host_Source      => To_Unbounded_String (Host_File_2),
               Target_Path      => To_Unbounded_String ("docs/a.txt"),
               Replacement_Path => Null_Unbounded_String));
         declare
            Replace_Plan : constant Archive.Writes.Plans.Write_Plan :=
              Archive.Writes.Plans.Build (Seed_Open.Index, Requests, Session => 10);
            Replaced_Path : constant String := Root & "/replaced.zip";
            Replaced_Zip : constant Archive.Writes.Results.Publish_Result :=
              Archive.Writes.Execution.Publish_Zip_Stored
                (Replaced_Path, Replace_Plan,
                 Source_Path => Seed_Path,
                 Source_Name => Seed_Path,
                 Overwrite => True);
            Replaced_Open : constant Archive.Archives.Readers.Dispatch.Open_Result :=
              Archive.Archives.Readers.Dispatch.Open_File (Replaced_Path);
            Replaced_Id : constant Archive.Types.Entry_Id :=
              Entry_Id_For (Replaced_Open.Index, "docs/a.txt");
            Replaced_Payload : constant Test_Stream_Result :=
              Stream_Dispatch_Payload_File
                (Replaced_Path,
                 "replaced.zip",
                 Archive.Archives.Index.Entry_For (Replaced_Open.Index, Replaced_Id));
         begin
            Assert (Replaced_Zip.Status = Archive.Writes.Results.Write_Completed,
                    "zip writer streams replace rewrite payload");
            Assert
              (Replaced_Open.Status = Archive.Archives.Errors.Ok
               and then Archive.Archives.Index.Physical_Count (Replaced_Open.Index) = 2
               and then Replaced_Payload.Status = Archive.Archives.Errors.Ok
               and then Replaced_Payload.Bytes_Written = 2
               and then Bytes_Of (Replaced_Payload) (1) = Zlib.Byte (Character'Pos ('g'))
               and then Bytes_Of (Replaced_Payload) (2) = Zlib.Byte (Character'Pos ('o')),
               "zip replace rewrite updates payload and preserves archive shape");
         end;
      end;
   end Test_Zip_Write_Adapter;

   procedure Test_Write_Dispatch (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      Root : constant String := "obj/write-dispatch-test";
      Host_File : constant String := Root & "/input.txt";
      Zip_Target : constant String := Root & "/dispatch-stream.zip";
      Zip_Bzip2_Target : constant String := Root & "/dispatch-stream-bzip2.zip";
      Zip_LZMA_Target : constant String := Root & "/dispatch-stream-lzma.zip";
      Zip_Zstd_Target : constant String := Root & "/dispatch-stream-zstd.zip";
      Tar_Gz_Target : constant String := Root & "/dispatch-stream.tar.gz";
      Seven_Zip_Target : constant String := Root & "/dispatch-stream.7z";
      Bzip2_Target : constant String := Root & "/dispatch-stream.bz2";
      Zstd_Target : constant String := Root & "/dispatch-stream.zst";
      File : Ada.Streams.Stream_IO.File_Type;
      Host_Data : constant Ada.Streams.Stream_Element_Array :=
        [1 => Ada.Streams.Stream_Element (Character'Pos ('o')),
         2 => Ada.Streams.Stream_Element (Character'Pos ('k'))];
      Physical : Archive.Archives.Entries.Entry_Vectors.Vector;
      Requests : Archive.Writes.Plans.Write_Request_Vectors.Vector;

      function Method_For
        (Index : Archive.Archives.Index.Archive_Index;
         Path  : String)
         return Archive.Archives.Entries.Compression_Method
      is
      begin
         for Raw_Id in 1 .. Archive.Archives.Index.Entry_Count (Index) loop
            declare
               Item : constant Archive.Archives.Entries.Archive_Entry :=
                 Archive.Archives.Index.Entry_For
                   (Index, Archive.Types.Entry_Id (Raw_Id));
            begin
               if To_String (Item.Original_Path) = Path then
                  return Item.Method;
               end if;
            end;
         end loop;
         return Archive.Archives.Entries.Unknown_Compression;
      end Method_For;
   begin
      if not Ada.Directories.Exists (Root) then
         Ada.Directories.Create_Path (Root);
      end if;
      if Ada.Directories.Exists (Zip_Target) then
         Ada.Directories.Delete_File (Zip_Target);
      end if;
      if Ada.Directories.Exists (Zip_Bzip2_Target) then
         Ada.Directories.Delete_File (Zip_Bzip2_Target);
      end if;
      if Ada.Directories.Exists (Zip_LZMA_Target) then
         Ada.Directories.Delete_File (Zip_LZMA_Target);
      end if;
      if Ada.Directories.Exists (Zip_Zstd_Target) then
         Ada.Directories.Delete_File (Zip_Zstd_Target);
      end if;
      if Ada.Directories.Exists (Tar_Gz_Target) then
         Ada.Directories.Delete_File (Tar_Gz_Target);
      end if;
      if Ada.Directories.Exists (Seven_Zip_Target) then
         Ada.Directories.Delete_File (Seven_Zip_Target);
      end if;
      if Ada.Directories.Exists (Bzip2_Target) then
         Ada.Directories.Delete_File (Bzip2_Target);
      end if;
      if Ada.Directories.Exists (Zstd_Target) then
         Ada.Directories.Delete_File (Zstd_Target);
      end if;

      Ada.Streams.Stream_IO.Create (File, Ada.Streams.Stream_IO.Out_File, Host_File);
      Ada.Streams.Stream_IO.Write (File, Host_Data);
      Ada.Streams.Stream_IO.Close (File);

      Requests.Append
        (Archive.Writes.Plans.Write_Request'
           (Action           => Archive.Writes.Plans.Add_File,
            Source_Entry     => Archive.Types.No_Entry,
            Host_Source      => To_Unbounded_String (Host_File),
            Target_Path      => To_Unbounded_String ("docs/readme.txt"),
            Replacement_Path => Null_Unbounded_String));

      declare
         Index : constant Archive.Archives.Index.Archive_Index :=
           Archive.Archives.Index.Build (Physical).Index;
         Plan : constant Archive.Writes.Plans.Write_Plan :=
           Archive.Writes.Plans.Build (Index, Requests, Session => 7);
         Unsupported : constant Archive.Writes.Results.Publish_Result :=
           Archive.Writes.Dispatch.Publish
             (Archive.Archives.Formats.Rar_Format,
              Root & "/unsupported.rar",
              Plan);
      begin
         Assert (Plan.Status = Archive.Writes.Plans.Write_Plan_Ready, "write dispatch plan ready");
         Assert (Unsupported.Status = Archive.Writes.Results.Write_Blocked_By_Plan,
                 "write dispatch rejects unsupported formats");
      end;

      declare
         Index : constant Archive.Archives.Index.Archive_Index :=
           Archive.Archives.Index.Build (Physical).Index;
         Plan : constant Archive.Writes.Plans.Write_Plan :=
           Archive.Writes.Plans.Build (Index, Requests, Session => 8);
         Zip_Published : constant Archive.Writes.Results.Publish_Result :=
           Archive.Writes.Dispatch.Publish
             (Archive.Archives.Formats.Zip_Format,
              Zip_Target,
              Plan,
              Method => Archive.Writes.Dispatch.Zip_Deflate_Method);
         Zip_Bzip2_Published : constant Archive.Writes.Results.Publish_Result :=
           Archive.Writes.Dispatch.Publish
             (Archive.Archives.Formats.Zip_Format,
              Zip_Bzip2_Target,
              Plan,
              Method => Archive.Writes.Dispatch.Zip_BZip2_Method);
         Zip_LZMA_Published : constant Archive.Writes.Results.Publish_Result :=
           Archive.Writes.Dispatch.Publish
             (Archive.Archives.Formats.Zip_Format,
              Zip_LZMA_Target,
              Plan,
              Method => Archive.Writes.Dispatch.Zip_LZMA_Method);
         Zip_Zstd_Published : constant Archive.Writes.Results.Publish_Result :=
           Archive.Writes.Dispatch.Publish
             (Archive.Archives.Formats.Zip_Format,
              Zip_Zstd_Target,
              Plan,
              Method => Archive.Writes.Dispatch.Zip_Zstd_Method);
         Tar_Gz_Published : constant Archive.Writes.Results.Publish_Result :=
           Archive.Writes.Dispatch.Publish
             (Archive.Archives.Formats.Tar_GZip_Format,
              Tar_Gz_Target,
              Plan);
         Seven_Zip_Published : constant Archive.Writes.Results.Publish_Result :=
           Archive.Writes.Dispatch.Publish
             (Archive.Archives.Formats.Seven_Zip_Format,
              Seven_Zip_Target,
              Plan);
         Bzip2_Published : constant Archive.Writes.Results.Publish_Result :=
           Archive.Writes.Dispatch.Publish
             (Archive.Archives.Formats.BZip2_Format,
              Bzip2_Target,
              Plan);
         Zstd_Published : constant Archive.Writes.Results.Publish_Result :=
           Archive.Writes.Dispatch.Publish
             (Archive.Archives.Formats.Zstd_Format,
              Zstd_Target,
              Plan);
         Zip_Opened : constant Archive.Archives.Readers.Dispatch.Open_Result :=
           Archive.Archives.Readers.Dispatch.Open_File (Zip_Target);
         Zip_Bzip2_Opened : constant Archive.Archives.Readers.Dispatch.Open_Result :=
           Archive.Archives.Readers.Dispatch.Open_File (Zip_Bzip2_Target);
         Zip_LZMA_Opened : constant Archive.Archives.Readers.Dispatch.Open_Result :=
           Archive.Archives.Readers.Dispatch.Open_File (Zip_LZMA_Target);
         Zip_Zstd_Opened : constant Archive.Archives.Readers.Dispatch.Open_Result :=
           Archive.Archives.Readers.Dispatch.Open_File (Zip_Zstd_Target);
         Tar_Gz_Opened : constant Archive.Archives.Readers.Dispatch.Open_Result :=
           Archive.Archives.Readers.Dispatch.Open_File
             (Tar_Gz_Target, Source_Name => Tar_Gz_Target, Retain_Backing => True);
         Seven_Zip_Opened : constant Archive.Archives.Readers.Dispatch.Open_Result :=
           Archive.Archives.Readers.Dispatch.Open_File (Seven_Zip_Target);
         Bzip2_Opened : constant Archive.Archives.Readers.Dispatch.Open_Result :=
           Archive.Archives.Readers.Dispatch.Open_File
             (Bzip2_Target, Source_Name => "dispatch-stream.bz2");
         Zstd_Opened : constant Archive.Archives.Readers.Dispatch.Open_Result :=
           Archive.Archives.Readers.Dispatch.Open_File
             (Zstd_Target, Source_Name => "dispatch-stream.zst");
      begin
         Assert
           (Zip_Published.Status = Archive.Writes.Results.Write_Completed,
            "write dispatch streams zip publication to file");
         Assert
           (Zip_Bzip2_Published.Status = Archive.Writes.Results.Write_Completed,
            "write dispatch publishes zip bzip2 payload through zlib");
         Assert
           (Zip_LZMA_Published.Status = Archive.Writes.Results.Write_Completed,
            "write dispatch publishes zip lzma payload through zlib");
         Assert
           (Zip_Zstd_Published.Status = Archive.Writes.Results.Write_Completed,
            "write dispatch publishes zip zstd payload through zlib");
         Assert
           (Tar_Gz_Published.Status = Archive.Writes.Results.Write_Completed,
            "write dispatch streams tar.gz publication to file");
         Assert
           (Seven_Zip_Published.Status = Archive.Writes.Results.Write_Completed,
            "write dispatch publishes 7z archive through zlib");
         Assert
           (Bzip2_Published.Status = Archive.Writes.Results.Write_Completed,
            "write dispatch publishes bzip2 archive through zlib");
         Assert
           (Zstd_Published.Status = Archive.Writes.Results.Write_Completed,
            "write dispatch publishes zstd archive through zlib");
         Assert
           (Zip_Opened.Status = Archive.Archives.Errors.Ok
            and then Zip_Opened.Format = Archive.Archives.Formats.Zip_Format,
            "streamed dispatch zip publication reopens");
         Assert
           (Zip_Bzip2_Opened.Status = Archive.Archives.Errors.Ok
            and then Method_For (Zip_Bzip2_Opened.Index, "docs/readme.txt") =
              Archive.Archives.Entries.BZip2_Compression,
            "write dispatch zip bzip2 publication reopens with method 12");
         Assert
           (Zip_LZMA_Opened.Status = Archive.Archives.Errors.Ok
            and then Method_For (Zip_LZMA_Opened.Index, "docs/readme.txt") =
              Archive.Archives.Entries.LZMA_Compression,
            "write dispatch zip lzma publication reopens with method 14");
         Assert
           (Zip_Zstd_Opened.Status = Archive.Archives.Errors.Ok
            and then Method_For (Zip_Zstd_Opened.Index, "docs/readme.txt") =
              Archive.Archives.Entries.Zstd_Compression,
            "write dispatch zip zstd publication reopens with method 20 or 93");
         Assert
           (Tar_Gz_Opened.Status = Archive.Archives.Errors.Ok
            and then Tar_Gz_Opened.Format = Archive.Archives.Formats.Tar_GZip_Format,
            "streamed dispatch tar.gz publication reopens");
         Assert
           (Seven_Zip_Opened.Status = Archive.Archives.Errors.Ok
            and then Seven_Zip_Opened.Format = Archive.Archives.Formats.Seven_Zip_Format
            and then Archive.Archives.Index.Physical_Count (Seven_Zip_Opened.Index) = 1,
            "write dispatch 7z publication reopens");
         Assert
           (Bzip2_Opened.Status = Archive.Archives.Errors.Ok
            and then Bzip2_Opened.Format = Archive.Archives.Formats.BZip2_Format
            and then Archive.Archives.Index.Physical_Count (Bzip2_Opened.Index) = 1,
            "write dispatch bzip2 publication reopens");
         Assert
           (Zstd_Opened.Status = Archive.Archives.Errors.Ok
            and then Zstd_Opened.Format = Archive.Archives.Formats.Zstd_Format
            and then Archive.Archives.Index.Physical_Count (Zstd_Opened.Index) = 1,
            "write dispatch zstd publication reopens");
      end;
   end Test_Write_Dispatch;

   procedure Test_Write_Service (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      Root      : constant String := "obj/write-service-test";
      Host_File : constant String := Root & "/input.txt";
      Target    : constant String := Root & "/saved.zip";
      Other_Target : constant String := Root & "/saved-copy.zip";
      Config    : constant Archive.UI.Shell_Configuration :=
        (Width => 1024,
         Height => 720,
         Locale => To_Unbounded_String ("en"),
         Line_Height => 20);
      Existing  : constant Zlib.Byte_Array :=
        [1 => Zlib.Byte (Character'Pos ('o')),
         2 => Zlib.Byte (Character'Pos ('l')),
         3 => Zlib.Byte (Character'Pos ('d'))];
      Model     : Archive.Model.Application_Model;
      Physical  : Archive.Archives.Entries.Entry_Vectors.Vector;

      procedure Write_Local (Path : String; Bytes : Zlib.Byte_Array) is
         File : Ada.Streams.Stream_IO.File_Type;
         Data : Ada.Streams.Stream_Element_Array (1 .. Ada.Streams.Stream_Element_Offset (Bytes'Length));
      begin
         for Index in Bytes'Range loop
            Data (Ada.Streams.Stream_Element_Offset (Index)) := Ada.Streams.Stream_Element (Bytes (Index));
         end loop;
         Ada.Streams.Stream_IO.Create (File, Ada.Streams.Stream_IO.Out_File, Path);
         Ada.Streams.Stream_IO.Write (File, Data);
         Ada.Streams.Stream_IO.Close (File);
      end Write_Local;
   begin
      if not Ada.Directories.Exists (Root) then
         Ada.Directories.Create_Path (Root);
      end if;
      if Ada.Directories.Exists (Target) then
         Ada.Directories.Delete_File (Target);
      end if;
      if Ada.Directories.Exists (Other_Target) then
         Ada.Directories.Delete_File (Other_Target);
      end if;

      Write_Local
        (Host_File,
         [1 => Zlib.Byte (Character'Pos ('o')),
          2 => Zlib.Byte (Character'Pos ('k'))]);

      Archive.Model.Initialize (Model);
      declare
         Build : constant Archive.Archives.Index.Build_Result :=
           Archive.Archives.Index.Build (Physical);
      begin
         Archive.Model.Publish_Archive_Index
           (Model, Target, Build.Index, Archive.Archives.Formats.Zip_Format);
      end;

      Archive.Model.Plan_Add_File (Model, Host_File, "docs/readme.txt");
      declare
         Result : constant Archive.Writes.Service.Save_Result :=
           Archive.Writes.Service.Save_As (Model, Target);
         Opened : constant Archive.Archives.Readers.Dispatch.Open_Result :=
           Archive.Archives.Readers.Dispatch.Open_File (Target);
      begin
         Assert (Result.Status = Archive.Writes.Service.Save_Completed,
                 "write service saves archive through file-backed deflate publisher");
         Assert (Result.Payload_Status = Archive.Archives.Errors.Ok,
                 "write service records successful payload build");
         Assert (Result.Publish_Status = Archive.Writes.Results.Write_Completed,
                 "write service records successful publish");
         Assert (Opened.Status = Archive.Archives.Errors.Ok,
                 "write service output reopens as archive");
         Assert (Archive.Model.Lifecycle (Model) = Archive.Model.Archive_Ready,
                 "write service successful save returns model to ready");
         Assert (not Archive.Model.Has_Pending_Writes (Model),
                 "write service successful save clears pending writes");
         Assert (Archive.Model.Source_Path (Model) = Target,
                 "write service publishes saved archive as active source");
         Assert
           (Archive.Model.Source_Fingerprint (Model).Status =
              Archive.Source_Monitoring.Source_Ready,
            "write service records saved archive fingerprint");
         Assert
           (Archive.Archives.Index.Physical_Count (Archive.Model.Published_Index (Model)) = 1,
            "write service publishes reopened saved archive index");
         Assert
           (Archive.Model.Last_Write_Status (Model) = Archive.Writes.Results.Write_Completed,
            "write service records successful write status in model");
         Assert
           (Archive.UI.Build_Shell (Model, Config).Write.Last_Status =
              Archive.Writes.Results.Write_Completed,
            "write service exposes successful write status through ui snapshot");
      end;

      Archive.Model.Plan_Add_File (Model, Host_File, "docs/in-place.txt");
      declare
         Previous_Source : constant String := Archive.Model.Source_Path (Model);
         Result : constant Archive.Writes.Service.Save_Result :=
           Archive.Writes.Service.Save (Model);
         Opened : constant Archive.Archives.Readers.Dispatch.Open_Result :=
           Archive.Archives.Readers.Dispatch.Open_File (Target);
      begin
         Assert (Result.Status = Archive.Writes.Service.Save_Completed,
                 "write service saves pending changes in place to active source");
         Assert (Result.Publish_Status = Archive.Writes.Results.Write_Completed,
                 "in-place save records successful publish");
         Assert (Archive.Model.Source_Path (Model) = Previous_Source,
                 "in-place save keeps the active source path");
         Assert (Opened.Status = Archive.Archives.Errors.Ok,
                 "in-place saved archive reopens");
         Assert
           (Archive.Archives.Index.Physical_Count (Opened.Index) = 2,
            "in-place save publishes updated archive contents");
         Assert (not Archive.Model.Has_Pending_Writes (Model),
                 "in-place save clears pending writes");
      end;

      Archive.Model.Plan_Add_File (Model, Host_File, "docs/second.txt");
      Write_Local (Other_Target, Existing);
      declare
         Result  : constant Archive.Writes.Service.Save_Result :=
           Archive.Writes.Service.Save_As (Model, Other_Target, Overwrite => False);
         Written : constant Zlib.Byte_Array := Read_All_Bytes (Other_Target);
      begin
         Assert (Result.Status = Archive.Writes.Service.Save_Publish_Failed,
                 "write service reports blocked publish");
         Assert (Result.Publish_Status = Archive.Writes.Results.Write_Blocked_By_Plan,
                 "write service preserves publisher status");
         Assert (Archive.Model.Lifecycle (Model) = Archive.Model.Archive_Save_Failed,
                 "blocked publish marks model save failed");
         Assert (Archive.Model.Has_Pending_Writes (Model),
                 "blocked publish keeps pending write plan");
         Assert
           (Archive.Model.Last_Write_Status (Model) =
              Archive.Writes.Results.Write_Blocked_By_Plan,
            "blocked publish records typed write status in model");
         Assert
           (Archive.UI.Build_Shell (Model, Config).Write.Last_Status =
              Archive.Writes.Results.Write_Blocked_By_Plan,
            "blocked publish exposes typed write status through ui snapshot");
         Assert
           (Written'Length = Existing'Length
            and then Written (1) = Existing (1)
            and then Written (2) = Existing (2)
            and then Written (3) = Existing (3),
            "blocked publish preserves existing archive bytes");
      end;

      declare
         Result : constant Archive.Writes.Service.Save_Result :=
           Archive.Writes.Service.Save_As (Model, Other_Target, Overwrite => True);
      begin
         Assert (Result.Status = Archive.Writes.Service.Save_Completed,
                 "write service overwrite publishes replacement");
         Assert (Archive.Model.Lifecycle (Model) = Archive.Model.Archive_Ready,
                 "write service overwrite returns model to ready");
         Assert
           (Archive.Model.Last_Write_Status (Model) = Archive.Writes.Results.Write_Completed,
           "write service overwrite records successful write status");
      end;

      declare
         Guarded_Model : Archive.Model.Application_Model;
         Guarded_Target : constant String := Root & "/guarded.zip";
         Initial : constant Zlib.Byte_Array := One_File_Zip;
         Replaced : constant Zlib.Byte_Array :=
           One_File_Zip (Data_Descriptor => True, Archive_Comment_Length => 3);
      begin
         Write_Local (Guarded_Target, Initial);
         Archive.Model.Initialize (Guarded_Model);
         declare
            Build : constant Archive.Archives.Index.Build_Result :=
              Archive.Archives.Index.Build (Physical);
         begin
            Archive.Model.Publish_Archive_Index
              (Guarded_Model,
               Guarded_Target,
               Build.Index,
               Archive.Archives.Formats.Zip_Format);
            Archive.Model.Set_Source_Fingerprint
              (Guarded_Model,
               Archive.Source_Monitoring.Fingerprint (Guarded_Target));
         end;

         Archive.Model.Plan_Add_File (Guarded_Model, Host_File, "docs/guarded.txt");
         Write_Local (Guarded_Target, Replaced);
         declare
            Result : constant Archive.Writes.Service.Save_Result :=
              Archive.Writes.Service.Save_As
                (Guarded_Model, Guarded_Target, Overwrite => True);
            Written : constant Zlib.Byte_Array := Read_All_Bytes (Guarded_Target);
         begin
            Assert (Result.Status = Archive.Writes.Service.Save_Publish_Failed,
                    "write service rejects save when source archive was replaced");
            Assert
              (Result.Publish_Status =
                 Archive.Writes.Results.Write_Failed_Source_Changed,
               "source replacement reports typed write status");
            Assert (Archive.Model.Lifecycle (Guarded_Model) = Archive.Model.Archive_Save_Failed,
                    "source replacement marks model save failed");
            Assert (Archive.Model.Has_Pending_Writes (Guarded_Model),
                    "source replacement keeps pending write plan");
            Assert
              (Written'Length = Replaced'Length
               and then Written (1) = Replaced (1)
               and then Written (Written'Last) = Replaced (Replaced'Last),
               "source replacement leaves replacement archive untouched");
         end;
      end;
   end Test_Write_Service;

   procedure Test_Extraction_Execution (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      Root : constant String := "obj/extraction-execution-test";
      Payload : constant Zlib.Byte_Array :=
        [1 => Zlib.Byte (Character'Pos ('o')),
         2 => Zlib.Byte (Character'Pos ('k'))];
      Replacement : constant Zlib.Byte_Array :=
        [1 => Zlib.Byte (Character'Pos ('n')),
         2 => Zlib.Byte (Character'Pos ('e')),
         3 => Zlib.Byte (Character'Pos ('w'))];
      Safe_Plan : constant Archive.Extraction.Plans.Plan_Entry :=
        (Source => 1,
         Kind => Archive.Archives.Entries.Regular_File,
         Path => (Decision => Archive.Extraction.Paths.Path_Accepted,
                  Safety => Archive.Archives.Entries.Safe_Path,
                  Relative_Key => To_Unbounded_String ("dir/file.txt"),
                  Component_Count => 2),
         Conflict => False,
         Conflict_With => Archive.Types.No_Entry,
         Expected_CRC32 => (Present => False));
      Unsafe_Plan : constant Archive.Extraction.Plans.Plan_Entry :=
        (Source => 2,
         Kind => Archive.Archives.Entries.Regular_File,
         Path => (Decision => Archive.Extraction.Paths.Path_Blocked_Unsafe,
                  Safety => Archive.Archives.Entries.Parent_Traversal,
                  Relative_Key => To_Unbounded_String ("../outside.txt"),
                  Component_Count => 2),
         Conflict => False,
         Conflict_With => Archive.Types.No_Entry,
         Expected_CRC32 => (Present => False));
      Checked_Plan : constant Archive.Extraction.Plans.Plan_Entry :=
        (Source => 3,
         Kind => Archive.Archives.Entries.Regular_File,
         Path => (Decision => Archive.Extraction.Paths.Path_Accepted,
                  Safety => Archive.Archives.Entries.Safe_Path,
                  Relative_Key => To_Unbounded_String ("dir/checked.txt"),
                  Component_Count => 2),
         Conflict => False,
         Conflict_With => Archive.Types.No_Entry,
         Expected_CRC32 =>
           (Present => True,
            Value => CRC32_Compute (Payload)));
      Directory_Plan : constant Archive.Extraction.Plans.Plan_Entry :=
        (Source => 4,
         Kind => Archive.Archives.Entries.Directory,
         Path => (Decision => Archive.Extraction.Paths.Path_Accepted,
                  Safety => Archive.Archives.Entries.Safe_Path,
                  Relative_Key => To_Unbounded_String ("dir/sub"),
                  Component_Count => 2),
         Conflict => False,
         Conflict_With => Archive.Types.No_Entry,
         Expected_CRC32 => (Present => False));

      function Publish_Test_File
        (Plan             : Archive.Extraction.Plans.Plan_Entry;
         Bytes            : Zlib.Byte_Array;
         Overwrite        : Boolean := False;
         Max_Output_Bytes : Archive.Resource_Limits.Limit_Value :=
           Archive.Resource_Limits.Default_Configured
             (Archive.Resource_Limits.Per_Entry_Extraction_Output))
         return Archive.Extraction.Results.File_Result
      is
         Written : Archive.Resource_Limits.Limit_Value := 0;

         function Provider
           (Source   : Archive.Types.Entry_Id;
            Consumer : not null Archive.Extraction.Execution.Payload_Chunk_Consumer)
            return Archive.Extraction.Execution.Stream_Payload_Result
         is
            pragma Unreferenced (Source);
            Continue : Boolean := True;
         begin
            Consumer.all (Bytes, Continue);
            return
              (Status =>
                 (if Continue
                  then Archive.Extraction.Results.Completed
                  else Archive.Extraction.Results.Cancelled),
               Bytes_Written => Bytes'Length);
         end Provider;
      begin
         return
           Archive.Extraction.Execution.Publish_File_Stream
             (Root, Plan, Provider'Unrestricted_Access, Written,
              Overwrite => Overwrite,
              Max_Output_Bytes => Max_Output_Bytes);
      end Publish_Test_File;
   begin
      if Ada.Directories.Exists (Root & "/dir/file.txt") then
         Ada.Directories.Delete_File (Root & "/dir/file.txt");
      end if;
      if Ada.Directories.Exists (Root & "/dir/checked.txt") then
         Ada.Directories.Delete_File (Root & "/dir/checked.txt");
      end if;
      if Ada.Directories.Exists (Root & "/dir/sub") then
         Ada.Directories.Delete_Tree (Root & "/dir/sub");
      end if;
      if not Ada.Directories.Exists (Root) then
         Ada.Directories.Create_Path (Root);
      end if;

      declare
         Result : constant Archive.Extraction.Results.File_Result :=
           Publish_Test_File (Safe_Plan, Payload);
         Written : constant Zlib.Byte_Array := Read_All_Bytes (Root & "/dir/file.txt");
      begin
         Assert (Result.Status = Archive.Extraction.Results.Completed, "safe file publishes");
         Assert
           (Written'Length = 2
            and then Written (1) = Zlib.Byte (Character'Pos ('o'))
            and then Written (2) = Zlib.Byte (Character'Pos ('k')),
            "published file has payload bytes");
      end;

      declare
         Stream_Root : constant String := Root & "/stream";
         Stream_Plan : constant Archive.Extraction.Plans.Plan_Entry :=
           (Source => 9,
            Kind => Archive.Archives.Entries.Regular_File,
            Path => (Decision => Archive.Extraction.Paths.Path_Accepted,
                     Safety => Archive.Archives.Entries.Safe_Path,
                     Relative_Key => To_Unbounded_String ("streamed.bin"),
                     Component_Count => 1),
            Conflict => False,
            Conflict_With => Archive.Types.No_Entry,
            Expected_CRC32 =>
              (Present => True,
               Value => CRC32_Compute (Replacement)));
         Plan : Archive.Extraction.Plans.Extraction_Plan;
         Calls : Natural := 0;

         function Stream_For
           (Source   : Archive.Types.Entry_Id;
            Consumer : not null Archive.Extraction.Execution.Payload_Chunk_Consumer)
            return Archive.Extraction.Execution.Stream_Payload_Result
         is
            Continue : Boolean := True;
         begin
            Assert (Source = 9, "streaming extraction provider receives stable entry id");
            Consumer.all (Replacement (1 .. 1), Continue);
            Calls := Calls + 1;
            if Continue then
               Consumer.all (Replacement (2 .. Replacement'Last), Continue);
               Calls := Calls + 1;
            end if;
            return
              (Status =>
                 (if Continue
                  then Archive.Extraction.Results.Completed
                  else Archive.Extraction.Results.Cancelled),
               Bytes_Written => Replacement'Length);
         end Stream_For;
      begin
         if Ada.Directories.Exists (Stream_Root) then
            Ada.Directories.Delete_Tree (Stream_Root);
         end if;
         Plan.Status := Archive.Extraction.Plans.Plan_Ready;
         Plan.Session := 29;
         Plan.Entries.Append (Stream_Plan);
         Plan.Requested_Count := 1;

         declare
            Executed : constant Archive.Extraction.Results.Plan_Result :=
              Archive.Extraction.Execution.Execute_Plan_Streaming
                (Stream_Root, Plan, Stream_For'Unrestricted_Access,
                 Per_Entry_Limit => 10,
                 Total_Limit => 10);
            Written : constant Zlib.Byte_Array := Read_All_Bytes (Stream_Root & "/streamed.bin");
         begin
            Assert (Executed.Status = Archive.Extraction.Results.Execution_Completed,
                    "streaming extraction executor completes");
            Assert (Calls = 2, "streaming extraction provider emits multiple chunks");
            Assert (Written = Replacement, "streaming extraction publishes concatenated chunks");
         end;
      end;

      declare
         Result : constant Archive.Extraction.Results.File_Result :=
           Publish_Test_File (Safe_Plan, Replacement);
         Written : constant Zlib.Byte_Array := Read_All_Bytes (Root & "/dir/file.txt");
      begin
         Assert (Result.Status = Archive.Extraction.Results.Blocked_By_Plan,
                 "existing target blocks without overwrite");
         Assert
           (Written'Length = 2
            and then Written (1) = Zlib.Byte (Character'Pos ('o'))
            and then Written (2) = Zlib.Byte (Character'Pos ('k')),
            "blocked overwrite preserves old payload");
      end;

      declare
         Result : constant Archive.Extraction.Results.File_Result :=
           Publish_Test_File (Safe_Plan, Replacement, Overwrite => True);
         Written : constant Zlib.Byte_Array := Read_All_Bytes (Root & "/dir/file.txt");
      begin
         Assert (Result.Status = Archive.Extraction.Results.Completed,
                 "explicit overwrite publishes");
         Assert
           (Written'Length = 3
            and then Written (1) = Zlib.Byte (Character'Pos ('n'))
            and then Written (2) = Zlib.Byte (Character'Pos ('e'))
            and then Written (3) = Zlib.Byte (Character'Pos ('w')),
            "overwrite replaces payload");
      end;

      declare
         Result : constant Archive.Extraction.Results.File_Result :=
           Publish_Test_File (Unsafe_Plan, Payload);
      begin
         Assert (Result.Status = Archive.Extraction.Results.Blocked_By_Plan,
                 "unsafe plan is blocked before write");
         Assert (not Ada.Directories.Exists ("obj/outside.txt"), "unsafe output is not written");
      end;

      declare
         Result : constant Archive.Extraction.Results.File_Result :=
           Publish_Test_File
             (Safe_Plan, Replacement, Overwrite => True, Max_Output_Bytes => 2);
      begin
         Assert (Result.Status = Archive.Extraction.Results.Failed_Limit,
                 "per-entry extraction output limit blocks publication");
      end;

      declare
         Result : constant Archive.Extraction.Results.File_Result :=
           Archive.Extraction.Execution.Publish_Directory (Root, Directory_Plan);
         Wrong_Kind : constant Archive.Extraction.Results.File_Result :=
           Publish_Test_File (Directory_Plan, Payload);
      begin
         Assert (Result.Status = Archive.Extraction.Results.Completed,
                 "directory extraction creates directory output");
         Assert (Ada.Directories.Exists (Root & "/dir/sub")
                 and then Ada.Directories.Kind (Root & "/dir/sub") = Ada.Directories.Directory,
                 "directory extraction publishes a directory");
         Assert (Wrong_Kind.Status = Archive.Extraction.Results.Blocked_By_Plan,
                 "directory plan cannot be published through file executor");
      end;

      declare
         Initial : constant Archive.Extraction.Results.File_Result :=
           Publish_Test_File (Checked_Plan, Payload);
         Failed : constant Archive.Extraction.Results.File_Result :=
           Publish_Test_File (Checked_Plan, Replacement, Overwrite => True);
         Written : constant Zlib.Byte_Array := Read_All_Bytes (Root & "/dir/checked.txt");
      begin
         Assert (Initial.Status = Archive.Extraction.Results.Completed,
                 "checksum-protected extraction publishes matching payload");
         Assert (Failed.Status = Archive.Extraction.Results.Failed_Checksum,
                 "checksum mismatch blocks extraction publication");
         Assert
           (Written'Length = 2
            and then Written (1) = Zlib.Byte (Character'Pos ('o'))
            and then Written (2) = Zlib.Byte (Character'Pos ('k')),
            "checksum failure preserves previously published output");
      end;

      declare
         Plan_Root : constant String := Root & "/plan";
         Physical  : Archive.Archives.Entries.Entry_Vectors.Vector;

         function Payload_For
           (Source   : Archive.Types.Entry_Id;
            Consumer : not null Archive.Extraction.Execution.Payload_Chunk_Consumer)
            return Archive.Extraction.Execution.Stream_Payload_Result
         is
            Continue : Boolean := True;
         begin
            if Source = 3 then
               Consumer.all (Payload, Continue);
               return
                 (Status =>
                    (if Continue
                     then Archive.Extraction.Results.Completed
                     else Archive.Extraction.Results.Cancelled),
                  Bytes_Written => Payload'Length);
            elsif Source = 4 then
               Consumer.all (Replacement, Continue);
               return
                 (Status =>
                    (if Continue
                     then Archive.Extraction.Results.Completed
                     else Archive.Extraction.Results.Cancelled),
                  Bytes_Written => Replacement'Length);
            else
               Consumer.all ([1 => Zlib.Byte (0)], Continue);
               return
                 (Status =>
                    (if Continue
                     then Archive.Extraction.Results.Completed
                     else Archive.Extraction.Results.Cancelled),
                  Bytes_Written => 1);
            end if;
         end Payload_For;
      begin
         if Ada.Directories.Exists (Plan_Root) then
            Ada.Directories.Delete_Tree (Plan_Root);
         end if;

         Physical.Append (Fixture_Entry ("bundle/", Archive.Archives.Entries.Directory));
         Physical.Append (Fixture_Entry ("bundle/one.txt"));
         Physical.Append (Fixture_Entry ("bundle/two.txt"));

         declare
            Build     : constant Archive.Archives.Index.Build_Result :=
              Archive.Archives.Index.Build (Physical);
            Selection : Archive.Types.Entry_Id_Vectors.Vector;
         begin
            Selection.Append (2);

            declare
               Plan : constant Archive.Extraction.Plans.Extraction_Plan :=
                 Archive.Extraction.Plans.Build (Build.Index, Selection, Session => 21);
               Executed : constant Archive.Extraction.Results.Plan_Result :=
                 Archive.Extraction.Execution.Execute_Plan_Streaming
                   (Plan_Root, Plan, Payload_For'Unrestricted_Access);
               One : constant Zlib.Byte_Array :=
                 Read_All_Bytes (Plan_Root & "/bundle/one.txt");
               Two : constant Zlib.Byte_Array :=
                 Read_All_Bytes (Plan_Root & "/bundle/two.txt");
            begin
               Assert (Plan.Status = Archive.Extraction.Plans.Plan_Ready,
                       "aggregate extraction plan is ready");
               Assert (Executed.Status = Archive.Extraction.Results.Execution_Completed,
                       "aggregate extraction completes");
               Assert (Executed.Completed_Count = 3
                       and then Executed.Failed_Count = 0
                       and then Executed.Blocked_Count = 0,
                       "aggregate extraction reports completed directory and files");
               Assert (One'Length = Payload'Length and then One (1) = Payload (1),
                       "aggregate extraction writes first file payload");
               Assert (Two'Length = Replacement'Length and then Two (1) = Replacement (1),
                       "aggregate extraction writes second file payload");
            end;
         end;
      end;

      declare
         Plan_Root : constant String := Root & "/partial";
         Physical  : Archive.Archives.Entries.Entry_Vectors.Vector;
         Bad       : Archive.Archives.Entries.Archive_Entry :=
           Fixture_Entry ("bundle/bad.txt");

         function Payload_For
           (Source   : Archive.Types.Entry_Id;
            Consumer : not null Archive.Extraction.Execution.Payload_Chunk_Consumer)
            return Archive.Extraction.Execution.Stream_Payload_Result
         is
            Continue : Boolean := True;
         begin
            if Source = 3 then
               Consumer.all (Payload, Continue);
               return
                 (Status =>
                    (if Continue
                     then Archive.Extraction.Results.Completed
                     else Archive.Extraction.Results.Cancelled),
                  Bytes_Written => Payload'Length);
            elsif Source = 4 then
               Consumer.all (Replacement, Continue);
               return
                 (Status =>
                    (if Continue
                     then Archive.Extraction.Results.Completed
                     else Archive.Extraction.Results.Cancelled),
                  Bytes_Written => Replacement'Length);
            else
               Consumer.all ([1 => Zlib.Byte (0)], Continue);
               return
                 (Status =>
                    (if Continue
                     then Archive.Extraction.Results.Completed
                     else Archive.Extraction.Results.Cancelled),
                  Bytes_Written => 1);
            end if;
         end Payload_For;
      begin
         if Ada.Directories.Exists (Plan_Root) then
            Ada.Directories.Delete_Tree (Plan_Root);
         end if;

         Bad.CRC32 := (Present => True, Value => CRC32_Compute (Payload));
         Physical.Append (Fixture_Entry ("bundle/", Archive.Archives.Entries.Directory));
         Physical.Append (Fixture_Entry ("bundle/good.txt"));
         Physical.Append (Bad);

         declare
            Build     : constant Archive.Archives.Index.Build_Result :=
              Archive.Archives.Index.Build (Physical);
            Selection : Archive.Types.Entry_Id_Vectors.Vector;
         begin
            Selection.Append (2);

            declare
               Plan : constant Archive.Extraction.Plans.Extraction_Plan :=
                 Archive.Extraction.Plans.Build (Build.Index, Selection, Session => 22);
               Executed : constant Archive.Extraction.Results.Plan_Result :=
                 Archive.Extraction.Execution.Execute_Plan_Streaming
                   (Plan_Root, Plan, Payload_For'Unrestricted_Access);
            begin
               Assert (Executed.Status = Archive.Extraction.Results.Execution_Partial,
                       "aggregate extraction reports partial completion after checksum failure");
               Assert (Executed.Completed_Count = 2
                       and then Executed.Failed_Count = 1
                       and then Executed.Last_Status = Archive.Extraction.Results.Failed_Checksum,
                       "aggregate extraction stops after first failed entry");
               Assert (Ada.Directories.Exists (Plan_Root & "/bundle/good.txt"),
                       "partial extraction keeps already published valid file");
               Assert (not Ada.Directories.Exists (Plan_Root & "/bundle/bad.txt"),
                       "partial extraction does not publish checksum-failed file");
            end;
         end;
      end;

      declare
         Plan_Root : constant String := Root & "/total-limit";
         Physical  : Archive.Archives.Entries.Entry_Vectors.Vector;

         function Payload_For
           (Source   : Archive.Types.Entry_Id;
            Consumer : not null Archive.Extraction.Execution.Payload_Chunk_Consumer)
            return Archive.Extraction.Execution.Stream_Payload_Result
         is
            pragma Unreferenced (Source);
            Continue : Boolean := True;
         begin
            Consumer.all (Replacement, Continue);
            return
              (Status =>
                 (if Continue
                  then Archive.Extraction.Results.Completed
                  else Archive.Extraction.Results.Cancelled),
               Bytes_Written => Replacement'Length);
         end Payload_For;
      begin
         if Ada.Directories.Exists (Plan_Root) then
            Ada.Directories.Delete_Tree (Plan_Root);
         end if;

         Physical.Append (Fixture_Entry ("one.txt"));
         Physical.Append (Fixture_Entry ("two.txt"));

         declare
            Build     : constant Archive.Archives.Index.Build_Result :=
              Archive.Archives.Index.Build (Physical);
            Selection : Archive.Types.Entry_Id_Vectors.Vector;
         begin
            Selection.Append (2);
            Selection.Append (3);

            declare
               Plan : constant Archive.Extraction.Plans.Extraction_Plan :=
                 Archive.Extraction.Plans.Build (Build.Index, Selection, Session => 26);
               Executed : constant Archive.Extraction.Results.Plan_Result :=
                 Archive.Extraction.Execution.Execute_Plan_Streaming
                   (Plan_Root, Plan, Payload_For'Unrestricted_Access,
                    Total_Limit => 4);
            begin
               Assert (Executed.Status = Archive.Extraction.Results.Execution_Partial,
                       "total extraction output limit reports partial completion");
               Assert (Executed.Completed_Count = 1
                       and then Executed.Failed_Count = 1
                       and then Executed.Last_Status = Archive.Extraction.Results.Failed_Limit,
                       "total extraction output limit stops before exceeding limit");
               Assert (Ada.Directories.Exists (Plan_Root & "/one.txt"),
                       "total limit keeps first valid output");
               Assert (not Ada.Directories.Exists (Plan_Root & "/two.txt"),
                       "total limit does not publish overflowing output");
            end;
         end;
      end;

      declare
         Plan_Root : constant String := Root & "/cancel-before";
         Physical  : Archive.Archives.Entries.Entry_Vectors.Vector;

         function Payload_For
           (Source   : Archive.Types.Entry_Id;
            Consumer : not null Archive.Extraction.Execution.Payload_Chunk_Consumer)
            return Archive.Extraction.Execution.Stream_Payload_Result
         is
            pragma Unreferenced (Source);
            Continue : Boolean := True;
         begin
            Consumer.all (Payload, Continue);
            return
              (Status =>
                 (if Continue
                  then Archive.Extraction.Results.Completed
                  else Archive.Extraction.Results.Cancelled),
               Bytes_Written => Payload'Length);
         end Payload_For;

         function Is_Cancelled return Boolean is
         begin
            return True;
         end Is_Cancelled;
      begin
         if Ada.Directories.Exists (Plan_Root) then
            Ada.Directories.Delete_Tree (Plan_Root);
         end if;

         Physical.Append (Fixture_Entry ("cancel.txt"));

         declare
            Build     : constant Archive.Archives.Index.Build_Result :=
              Archive.Archives.Index.Build (Physical);
            Selection : Archive.Types.Entry_Id_Vectors.Vector;
         begin
            Selection.Append (2);

            declare
               Plan : constant Archive.Extraction.Plans.Extraction_Plan :=
                 Archive.Extraction.Plans.Build (Build.Index, Selection, Session => 23);
               Executed : constant Archive.Extraction.Results.Plan_Result :=
                 Archive.Extraction.Execution.Execute_Plan_Streaming
                   (Plan_Root, Plan, Payload_For'Unrestricted_Access,
                    Cancelled => Is_Cancelled'Unrestricted_Access);
            begin
               Assert (Executed.Status = Archive.Extraction.Results.Execution_Cancelled,
                       "aggregate extraction can cancel before publishing output");
               Assert (Executed.Completed_Count = 0
                       and then Executed.Last_Status = Archive.Extraction.Results.Cancelled,
                       "cancel-before reports no completed entries");
               Assert (not Ada.Directories.Exists (Plan_Root & "/cancel.txt"),
                       "cancel-before leaves no output file");
            end;
         end;
      end;

      declare
         Plan_Root : constant String := Root & "/cancel-after";
         Physical  : Archive.Archives.Entries.Entry_Vectors.Vector;
         Checks    : Natural := 0;

         function Payload_For
           (Source   : Archive.Types.Entry_Id;
            Consumer : not null Archive.Extraction.Execution.Payload_Chunk_Consumer)
            return Archive.Extraction.Execution.Stream_Payload_Result
         is
            pragma Unreferenced (Source);
            Continue : Boolean := True;
         begin
            Consumer.all (Payload, Continue);
            return
              (Status =>
                 (if Continue
                  then Archive.Extraction.Results.Completed
                  else Archive.Extraction.Results.Cancelled),
               Bytes_Written => Payload'Length);
         end Payload_For;

         function Is_Cancelled return Boolean is
         begin
            Checks := Checks + 1;
            return Checks >= 2;
         end Is_Cancelled;
      begin
         if Ada.Directories.Exists (Plan_Root) then
            Ada.Directories.Delete_Tree (Plan_Root);
         end if;

         Physical.Append (Fixture_Entry ("first.txt"));
         Physical.Append (Fixture_Entry ("second.txt"));

         declare
            Build     : constant Archive.Archives.Index.Build_Result :=
              Archive.Archives.Index.Build (Physical);
            Selection : Archive.Types.Entry_Id_Vectors.Vector;
         begin
            Selection.Append (2);
            Selection.Append (3);

            declare
               Plan : constant Archive.Extraction.Plans.Extraction_Plan :=
                 Archive.Extraction.Plans.Build (Build.Index, Selection, Session => 24);
               Executed : constant Archive.Extraction.Results.Plan_Result :=
                 Archive.Extraction.Execution.Execute_Plan_Streaming
                   (Plan_Root, Plan, Payload_For'Unrestricted_Access,
                    Cancelled => Is_Cancelled'Unrestricted_Access);
            begin
               Assert (Executed.Status = Archive.Extraction.Results.Execution_Partial,
                       "aggregate extraction reports partial result after mid-plan cancellation");
               Assert (Executed.Completed_Count = 1
                       and then Executed.Last_Status = Archive.Extraction.Results.Cancelled,
                       "mid-plan cancellation keeps completed count and cancelled status");
               Assert (Ada.Directories.Exists (Plan_Root & "/first.txt"),
                       "mid-plan cancellation keeps already published valid output");
               Assert (not Ada.Directories.Exists (Plan_Root & "/second.txt"),
                       "mid-plan cancellation stops before the next output");
            end;
         end;
      end;

      declare
         Plan_Root : constant String := Root & "/payload-failure";
         Physical  : Archive.Archives.Entries.Entry_Vectors.Vector;

         function Payload_For
           (Source   : Archive.Types.Entry_Id;
            Consumer : not null Archive.Extraction.Execution.Payload_Chunk_Consumer)
            return Archive.Extraction.Execution.Stream_Payload_Result
         is
            pragma Unreferenced (Source);
            pragma Unreferenced (Consumer);
         begin
            return
              (Status => Archive.Extraction.Results.Failed_Write,
               Bytes_Written => 0);
         end Payload_For;
      begin
         if Ada.Directories.Exists (Plan_Root) then
            Ada.Directories.Delete_Tree (Plan_Root);
         end if;

         Physical.Append (Fixture_Entry ("failed.txt"));

         declare
            Build     : constant Archive.Archives.Index.Build_Result :=
              Archive.Archives.Index.Build (Physical);
            Selection : Archive.Types.Entry_Id_Vectors.Vector;
         begin
            Selection.Append (2);

            declare
               Plan : constant Archive.Extraction.Plans.Extraction_Plan :=
                 Archive.Extraction.Plans.Build (Build.Index, Selection, Session => 25);
               Executed : constant Archive.Extraction.Results.Plan_Result :=
                 Archive.Extraction.Execution.Execute_Plan_Streaming
                   (Plan_Root, Plan, Payload_For'Unrestricted_Access);
            begin
               Assert (Executed.Status = Archive.Extraction.Results.Execution_Failed,
                       "aggregate extraction reports failed payload provider");
               Assert (Executed.Completed_Count = 0
                       and then Executed.Failed_Count = 1
                       and then Executed.Last_Status = Archive.Extraction.Results.Failed_Write,
                       "payload provider failure is counted without publication");
               Assert (not Ada.Directories.Exists (Plan_Root & "/failed.txt"),
                       "payload provider failure publishes no output");
            end;
         end;
      end;
   end Test_Extraction_Execution;

   procedure Test_Zip_Extract_Workflow (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      Root : constant String := "obj/zip-extract-workflow-test";
      Zip_Bytes : constant Zlib.Byte_Array := One_File_Zip;
      Zip_Path  : constant String := Root & "/sample.zip";
   begin
      if Ada.Directories.Exists (Root & "/a.txt") then
         Ada.Directories.Delete_File (Root & "/a.txt");
      end if;
      if not Ada.Directories.Exists (Root) then
         Ada.Directories.Create_Path (Root);
      end if;
      Write_Bytes (Zip_Path, Zip_Bytes);

      declare
         Opened : constant Archive.Archives.Readers.Dispatch.Open_Result :=
           Open_Dispatch (Zip_Bytes, Source_Name => "sample.zip");
         Item : constant Archive.Archives.Entries.Archive_Entry :=
           Archive.Archives.Index.Entry_For (Opened.Index, 2);
         Selection : Archive.Types.Entry_Id_Vectors.Vector;
      begin
         Assert (Opened.Status = Archive.Archives.Errors.Ok, "workflow zip dispatch succeeds");
         Selection.Append (2);

         declare
            Plan : constant Archive.Extraction.Plans.Extraction_Plan :=
              Archive.Extraction.Plans.Build (Opened.Index, Selection, Session => 1);
            Written_Count : Archive.Resource_Limits.Limit_Value := 0;

            function Provider
              (Source   : Archive.Types.Entry_Id;
               Consumer : not null Archive.Extraction.Execution.Payload_Chunk_Consumer)
               return Archive.Extraction.Execution.Stream_Payload_Result
            is
               Payload : constant Archive.Archives.Readers.Dispatch.Stream_Result :=
                 Archive.Archives.Readers.Dispatch.Stream_Payload_File
                   (Zip_Path, "sample.zip",
                    Archive.Archives.Index.Entry_For (Opened.Index, Source),
                    Consumer);
            begin
               return
                 (Status =>
                    (if Payload.Status = Archive.Archives.Errors.Ok
                     then Archive.Extraction.Results.Completed
                     elsif Payload.Status = Archive.Archives.Errors.Cancelled
                     then Archive.Extraction.Results.Cancelled
                     else Archive.Extraction.Results.Failed_Write),
                  Bytes_Written =>
                    Archive.Resource_Limits.Limit_Value (Payload.Bytes_Written));
            end Provider;

            Result : constant Archive.Extraction.Results.File_Result :=
              Archive.Extraction.Execution.Publish_File_Stream
                (Root, Plan.Entries.Element (1), Provider'Unrestricted_Access,
                 Written_Count);
            Written : constant Zlib.Byte_Array := Read_All_Bytes (Root & "/a.txt");
         begin
            Assert (Plan.Status = Archive.Extraction.Plans.Plan_Ready, "workflow extraction plan ready");
            Assert (Result.Status = Archive.Extraction.Results.Completed, "workflow extraction publishes");
            Assert (Written_Count = 3, "workflow streams expected payload byte count");
            Assert
              (Written'Length = 3
               and then Written (1) = Zlib.Byte (Character'Pos ('a'))
               and then Written (2) = Zlib.Byte (Character'Pos ('b'))
               and then Written (3) = Zlib.Byte (Character'Pos ('c')),
               "workflow output matches payload");
         end;
      end;
   end Test_Zip_Extract_Workflow;

   procedure Test_Format_Extract_Workflows (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      Root : constant String := "obj/format-extract-workflows-test";
      Plain : constant Zlib.Byte_Array :=
        [1 => Zlib.Byte (Character'Pos ('a')),
         2 => Zlib.Byte (Character'Pos ('b')),
         3 => Zlib.Byte (Character'Pos ('c'))];
      Gz_Status : Zlib.Status_Code;
      Tar_Gz_Status : Zlib.Status_Code;
      Gz : constant Zlib.Byte_Array := Zlib.GZip (Plain, Zlib.Fixed, Gz_Status);
      Tar_Gz : constant Zlib.Byte_Array := Zlib.GZip (One_File_Tar, Zlib.Fixed, Tar_Gz_Status);
      Zip_Deflate : constant Zlib.Byte_Array := One_File_Zip (Method => 8);

      procedure Run_Case
        (Label       : String;
         Bytes       : Zlib.Byte_Array;
         Source_Name : String;
         Entry_Id    : Archive.Types.Entry_Id;
         Output_Name : String)
      is
         Target : constant String := Root & "/" & Output_Name;
         Source_Path : constant String := Root & "/" & Source_Name;
      begin
         if Ada.Directories.Exists (Target) then
            Ada.Directories.Delete_File (Target);
         end if;
         Write_Bytes (Source_Path, Bytes);

         declare
            Opened : constant Archive.Archives.Readers.Dispatch.Open_Result :=
              Open_Dispatch (Bytes, Source_Name => Source_Name);
            Selection : Archive.Types.Entry_Id_Vectors.Vector;
         begin
            Assert (Opened.Status = Archive.Archives.Errors.Ok, Label & " opens");
            Selection.Append (Entry_Id);

            declare
               Plan : constant Archive.Extraction.Plans.Extraction_Plan :=
                 Archive.Extraction.Plans.Build (Opened.Index, Selection, Session => 9);
               Written_Count : Archive.Resource_Limits.Limit_Value := 0;

               function Provider
                 (Source   : Archive.Types.Entry_Id;
                  Consumer : not null Archive.Extraction.Execution.Payload_Chunk_Consumer)
                  return Archive.Extraction.Execution.Stream_Payload_Result
               is
                  Payload : constant Archive.Archives.Readers.Dispatch.Stream_Result :=
                    Archive.Archives.Readers.Dispatch.Stream_Payload_File
                      (Source_Path, Source_Name,
                       Archive.Archives.Index.Entry_For (Opened.Index, Source),
                       Consumer);
               begin
                  return
                    (Status =>
                       (if Payload.Status = Archive.Archives.Errors.Ok
                        then Archive.Extraction.Results.Completed
                        elsif Payload.Status = Archive.Archives.Errors.Cancelled
                        then Archive.Extraction.Results.Cancelled
                        else Archive.Extraction.Results.Failed_Write),
                     Bytes_Written =>
                       Archive.Resource_Limits.Limit_Value (Payload.Bytes_Written));
               end Provider;

               Result : constant Archive.Extraction.Results.File_Result :=
                 Archive.Extraction.Execution.Publish_File_Stream
                   (Root, Plan.Entries.Element (1), Provider'Unrestricted_Access,
                    Written_Count, Overwrite => True);
            begin
               Assert (Plan.Status = Archive.Extraction.Plans.Plan_Ready, Label & " extraction plan ready");
               Assert (Result.Status = Archive.Extraction.Results.Completed, Label & " extraction publishes");
               Assert (Written_Count > 0, Label & " streams payload bytes");
            end;
         end;
      end Run_Case;
   begin
      Assert (Gz_Status = Zlib.Ok, "multi-format gzip fixture builds");
      Assert (Tar_Gz_Status = Zlib.Ok, "multi-format tar.gz fixture builds");
      Assert (Zip_Deflate'Length > 0, "multi-format zip deflate fixture builds");

      if not Ada.Directories.Exists (Root) then
         Ada.Directories.Create_Path (Root);
      end if;

      Run_Case ("zip stored", One_File_Zip, "stored.zip", 2, "a.txt");
      Run_Case ("zip deflate", Zip_Deflate, "deflate.zip", 2, "a.txt");
      Run_Case ("gzip", Gz, "payload.txt.gz", 2, "payload.txt");
      Run_Case ("tar", One_File_Tar, "sample.tar", 3, "docs/readme.txt");
      Run_Case ("tar.gz", Tar_Gz, "sample.tar.gz", 3, "docs/readme.txt");
   end Test_Format_Extract_Workflows;

   procedure Test_Completion_Gate_Workflows (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      Root : constant String := "obj/completion-gate-workflows-test";
      Config : constant Archive.UI.Shell_Configuration :=
        (Width => 1280,
         Height => 800,
         Locale => To_Unbounded_String ("en"),
         Line_Height => 20);
      Plain : constant Zlib.Byte_Array :=
        [1 => Zlib.Byte (Character'Pos ('a')),
         2 => Zlib.Byte (Character'Pos ('b')),
         3 => Zlib.Byte (Character'Pos ('c'))];
      Gzip_Status : Zlib.Status_Code;
      Tar_Gzip_Status : Zlib.Status_Code;
      Gzip_Bytes : constant Zlib.Byte_Array := Zlib.GZip (Plain, Zlib.Fixed, Gzip_Status);
      Tar_Gzip_Bytes : constant Zlib.Byte_Array :=
        Zlib.GZip (One_File_Tar, Zlib.Fixed, Tar_Gzip_Status);
      Zip_Deflate_Bytes : constant Zlib.Byte_Array := One_File_Zip (Method => 8);

      function First_Regular
        (Index : Archive.Archives.Index.Archive_Index)
         return Archive.Archives.Entries.Archive_Entry
      is
      begin
         for Raw_Id in 1 .. Archive.Archives.Index.Entry_Count (Index) loop
            declare
               Item : constant Archive.Archives.Entries.Archive_Entry :=
                 Archive.Archives.Index.Entry_For
                   (Index, Archive.Types.Entry_Id (Raw_Id));
            begin
               if not Item.Synthetic
                 and then Item.Kind = Archive.Archives.Entries.Regular_File
               then
                  return Item;
               end if;
            end;
         end loop;

         Assert (False, "completion gate fixture has regular entry");
         return Archive.Archives.Entries.Archive_Entry'(others => <>);
      end First_Regular;

      procedure Run_Case
        (Label       : String;
         Bytes       : Zlib.Byte_Array;
         Source_Name : String;
         Saveable    : Boolean;
         Replace_On_Save : Boolean := False;
         Save_Method : Archive.Writes.Dispatch.Zip_Method :=
           Archive.Writes.Dispatch.Zip_Deflate_Method)
      is
         Source_Path : constant String := Root & "/" & Source_Name;
         Extract_Root : constant String := Root & "/extract-" & Label;
         Host_File : constant String := Root & "/host-" & Label & ".txt";
         Save_Path : constant String := Root & "/saved-" & Source_Name;
         Model : Archive.Model.Application_Model;
      begin
         Write_Bytes (Source_Path, Bytes);
         Write_Bytes
           (Host_File,
            [1 => Zlib.Byte (Character'Pos ('o')),
             2 => Zlib.Byte (Character'Pos ('k'))]);

         Archive.Model.Initialize (Model);
         declare
            Opened : constant Archive.Archives.Opening.Open_Attempt_Result :=
              Archive.Archives.Opening.Open_Path (Model, Source_Path);
            Shell : constant Archive.UI.Shell_Snapshot :=
              Archive.UI.Build_Shell (Model, Config);
         begin
            Assert
              (Opened.Status = Archive.Archives.Opening.Open_Completed,
               Label & " completion gate opens through model workflow");
            Assert (Archive.Model.Has_Index (Model), Label & " publishes immutable index");
            Assert (Shell.Content_View.Total_Rows > 0, Label & " displays archive root");
         end;

         declare
            Item : constant Archive.Archives.Entries.Archive_Entry :=
              First_Regular (Archive.Model.Published_Index (Model));
         begin
            if Item.Parent /= Archive.Types.No_Entry
              and then Item.Parent /= Archive.Archives.Index.Root_Id
                   (Archive.Model.Published_Index (Model))
            then
               Archive.Model.Set_Current_Directory (Model, Item.Parent);
            end if;

            declare
               Result : constant Archive.UI.Dispatch_Result :=
                 Archive.UI.Dispatch_Command
                   (Model, Archive.Commands.Select_Details_View_Command,
                    Archive.UI.Toolbar_Source);
            begin
               Assert (Result.Matched and then Result.Accepted,
                       Label & " switches to details view through command executor");
            end;

            Archive.Model.Set_Sorting
              (Model,
               Archive.View_Snapshots.Sort_By_Name,
               Archive.View_Snapshots.Ascending,
               Directories_First => True);
            Archive.Model.Set_Filter (Model, To_String (Item.Display_Name));
            declare
               Shell : constant Archive.UI.Shell_Snapshot :=
                 Archive.UI.Build_Shell (Model, Config);
            begin
               Assert
                 (Shell.Content_View.Mode = Archive.Types.Details_View
                  and then Shell.Content_View.Total_Rows >= 1,
                  Label & " sorts and filters visible rows");
            end;
            Archive.Model.Set_Filter (Model, "");

            Archive.Model.Select_Only (Model, Item.Id);
            Archive.Model.Start_Preview (Model, Item.Id);
            declare
               Acc : Archive.Preview.Preview_Accumulator (Capacity => 4096);
               Continue : Boolean := True;

               procedure Preview_Chunk
                 (Chunk : Zlib.Byte_Array;
                  Continue_Stream : in out Boolean)
               is
               begin
                  Archive.Preview.Append (Acc, Chunk, Continue);
                  Continue_Stream := Continue;
               end Preview_Chunk;

               Payload : Archive.Archives.Readers.Dispatch.Stream_Result;
            begin
               Archive.Preview.Initialize (Acc, (others => <>));
               Payload :=
                 Archive.Archives.Readers.Dispatch.Stream_Payload_File
                   (Source_Path, Source_Path, Item, Preview_Chunk'Access);
               Assert (Payload.Status = Archive.Archives.Errors.Ok,
                       Label & " streams preview payload");
               Assert
                 (Archive.Model.Publish_Preview
                    (Model,
                     Archive.Model.Current_Preview_Generation (Model),
                     Archive.Preview.Generate_Entry_From_Accumulator (Item, Acc)),
                  Label & " publishes current preview result");
               Assert
                 (Archive.UI.Build_Shell (Model, Config).Preview_Panel.Phase =
                    Archive.Model.Preview_Ready,
                  Label & " exposes ready preview through shell");
            end;

            declare
               Overlay : constant Archive.Verification.Overlays.Verification_Overlay :=
                 Archive.Verification.Archives.Verify_All_File
                   (Source_Path, Source_Path, Archive.Model.Published_Index (Model),
                    Archive.Model.Session_Generation (Model), 77);
            begin
               Assert
                 (Archive.Verification.Overlays.Entry_Count (Overlay) >= 1,
                  Label & " verifies archive payloads");
            end;

            Archive.Model.Plan_Selected_Extraction (Model);
            declare
               Plan : constant Archive.Extraction.Plans.Extraction_Plan :=
                 Archive.Model.Current_Extraction_Plan (Model);
               Extracted : constant Archive.Extraction.Service.Extract_Result :=
                 Archive.Extraction.Service.Extract_Planned (Model, Extract_Root);
            begin
               Assert (Plan.Status = Archive.Extraction.Plans.Plan_Ready,
                       Label & " builds ready extraction plan");
               Assert
                 (Extracted.Status = Archive.Extraction.Service.Extract_Completed,
                  Label & " extracts selected entry safely");
               Assert
                 (Ada.Directories.Exists
                    (Extract_Root & "/" & To_String (Plan.Entries.Element (1).Path.Relative_Key)),
                  Label & " validates extracted output path");
            end;

            if Saveable then
               if Replace_On_Save then
                  Archive.Model.Select_Only (Model, Item.Id);
                  Archive.Model.Plan_Selected_Replacement (Model, Host_File);
               else
                  Archive.Model.Plan_Add_File
                    (Model, Host_File, "added-" & Label & ".txt");
               end if;
               declare
                  Saved : constant Archive.Writes.Service.Save_Result :=
                    Archive.Writes.Service.Save_As
                      (Model, Save_Path, Method => Save_Method, Overwrite => True);
                  Reopened : constant Archive.Archives.Readers.Dispatch.Open_Result :=
                    Archive.Archives.Readers.Dispatch.Open_File
                      (Save_Path, Source_Name => Save_Path, Retain_Backing => True);
                  Verified : Archive.Verification.Overlays.Verification_Overlay;
               begin
                  Assert
                    (Saved.Status = Archive.Writes.Service.Save_Completed,
                     Label & " saves updated archive");
                  Assert
                    (Reopened.Status = Archive.Archives.Errors.Ok,
                     Label & " reopens saved archive");
                  Verified :=
                    Archive.Verification.Archives.Verify_All_File
                      (Save_Path, Save_Path, Reopened.Index,
                       Archive.Model.Session_Generation (Model), 88);
                  Assert
                    (Archive.Verification.Overlays.Entry_Count (Verified) >= 1,
                     Label & " verifies reopened saved archive");
               end;
            end if;

            Archive.Model.Close_Archive (Model);
            Assert
              (Archive.Model.Lifecycle (Model) = Archive.Model.No_Archive,
               Label & " closes cleanly");
         end;
      end Run_Case;
   begin
      Assert (Gzip_Status = Zlib.Ok, "completion gate gzip fixture builds");
      Assert (Tar_Gzip_Status = Zlib.Ok, "completion gate tar.gz fixture builds");

      if Ada.Directories.Exists (Root) then
         Ada.Directories.Delete_Tree (Root);
      end if;
      Ada.Directories.Create_Path (Root);

      Run_Case
        ("zip-stored", One_File_Zip, "stored.zip", Saveable => True,
         Save_Method => Archive.Writes.Dispatch.Zip_Stored_Method);
      Run_Case
        ("zip-deflate", Zip_Deflate_Bytes, "deflate.zip", Saveable => True,
         Save_Method => Archive.Writes.Dispatch.Zip_Deflate_Method);
      Run_Case ("tar", One_File_Tar, "sample.tar", Saveable => True);
      Run_Case ("tar-gzip", Tar_Gzip_Bytes, "sample.tar.gz", Saveable => True);
      Run_Case
        ("gzip", Gzip_Bytes, "payload.txt.gz", Saveable => True,
         Replace_On_Save => True);
   end Test_Completion_Gate_Workflows;

   procedure Write_Bytes (Path : String; Bytes : Zlib.Byte_Array) is
      File : Ada.Streams.Stream_IO.File_Type;
      Data : Ada.Streams.Stream_Element_Array (1 .. Ada.Streams.Stream_Element_Offset (Bytes'Length));
   begin
      for Index in Bytes'Range loop
         Data (Ada.Streams.Stream_Element_Offset (Index)) := Ada.Streams.Stream_Element (Bytes (Index));
      end loop;
      Ada.Streams.Stream_IO.Create (File, Ada.Streams.Stream_IO.Out_File, Path);
      Ada.Streams.Stream_IO.Write (File, Data);
      Ada.Streams.Stream_IO.Close (File);
   end Write_Bytes;

   procedure Test_Extraction_Service (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      Root      : constant String := "obj/extraction-service-test";
      Zip_Path  : constant String := Root & "/sample.zip";
      Dest      : constant String := Root & "/out";
      Model     : Archive.Model.Application_Model;
      Config    : constant Archive.UI.Shell_Configuration :=
        (Width => 1024,
         Height => 720,
         Locale => To_Unbounded_String ("en"),
         Line_Height => 20);
   begin
      if Ada.Directories.Exists (Root) then
         Ada.Directories.Delete_Tree (Root);
      end if;
      Ada.Directories.Create_Path (Root);
      Write_Bytes (Zip_Path, One_File_Zip);

      Archive.Model.Initialize (Model);
      declare
         Opened : constant Archive.Archives.Opening.Open_Attempt_Result :=
           Archive.Archives.Opening.Open_Path (Model, Zip_Path);
      begin
         Assert (Opened.Status = Archive.Archives.Opening.Open_Completed,
                 "extraction service opens source archive through model");
      end;

      Archive.Model.Plan_All_Extraction (Model);
      declare
         Extracted : constant Archive.Extraction.Service.Extract_Result :=
           Archive.Extraction.Service.Extract_Planned (Model, Dest);
         Written : constant Zlib.Byte_Array := Read_All_Bytes (Dest & "/a.txt");
      begin
         Assert (Extracted.Status = Archive.Extraction.Service.Extract_Completed,
                 "extraction service executes ready plan");
         Assert (Extracted.Plan_Status = Archive.Extraction.Results.Execution_Completed,
                 "extraction service reports completed plan execution");
         Assert (Extracted.Completed_Count = 1
                 and then Extracted.Failed_Count = 0
                 and then Extracted.Blocked_Count = 0,
                 "extraction service reports completed file count");
         Assert
           (Written'Length = 3
            and then Written (1) = Zlib.Byte (Character'Pos ('a'))
            and then Written (2) = Zlib.Byte (Character'Pos ('b'))
            and then Written (3) = Zlib.Byte (Character'Pos ('c')),
            "extraction service writes payload read through dispatch");
         Assert (Archive.Model.Extraction_Phase (Model) = Archive.Model.No_Extraction,
                 "successful extraction service clears planned state");
         Assert (Archive.Model.Notification (Model) = Archive.Model.Info_Notification,
                 "successful extraction service publishes info notification");
         Assert
           (Archive.Model.Last_Extraction_Status (Model) = Archive.Extraction.Results.Completed
            and then Archive.Model.Last_Extraction_Plan_Status (Model) =
              Archive.Extraction.Results.Execution_Completed,
            "successful extraction service records terminal execution status");
         Assert
           (Archive.Model.Last_Extraction_Completed_Count (Model) = 1
            and then Archive.Model.Last_Extraction_Failed_Count (Model) = 0
            and then Archive.Model.Last_Extraction_Blocked_Count (Model) = 0,
            "successful extraction service records execution counts in model");
         declare
            Shell : constant Archive.UI.Shell_Snapshot :=
              Archive.UI.Build_Shell (Model, Config);
         begin
            Assert
              (Shell.Extraction.Last_Status = Archive.Extraction.Results.Completed
               and then Shell.Extraction.Last_Plan_Status =
                 Archive.Extraction.Results.Execution_Completed,
               "ui shell extraction snapshot exposes terminal status");
            Assert
              (Shell.Extraction.Completed_Count = 1
               and then Shell.Extraction.Failed_Count = 0
               and then Shell.Extraction.Last_Blocked_Count = 0,
               "ui shell extraction snapshot exposes terminal counts");
         end;
         Assert
           (Archive.Localization.Text (Archive.Model.Notification_Key (Model)) =
              "Extraction completed.",
            "successful extraction notification is localized");
      end;

      Archive.Model.Select_Only (Model, 2);
      Archive.Model.Plan_Selected_Extraction (Model);
      Write_Bytes (Root & "/destination-file", [1 => Zlib.Byte (7)]);
      declare
         Rejected : constant Archive.Extraction.Service.Extract_Result :=
           Archive.Extraction.Service.Extract_Planned
             (Model, Root & "/destination-file");
      begin
         Assert (Rejected.Status = Archive.Extraction.Service.Extract_Destination_Failed,
                 "extraction service rejects file destination root");
         Assert (Rejected.Plan_Status = Archive.Extraction.Results.Execution_Blocked,
                 "invalid destination blocks plan execution");
         Assert (Archive.Model.Extraction_Phase (Model) = Archive.Model.Extraction_Planned,
                 "invalid destination keeps extraction plan for retry");
         Assert (Archive.Model.Notification (Model) = Archive.Model.Error_Notification,
                 "invalid destination publishes extraction failure notification");
         Assert
           (Archive.Model.Last_Extraction_Status (Model) =
              Archive.Extraction.Results.Blocked_By_Plan
            and then Archive.Model.Last_Extraction_Blocked_Count (Model) = 1,
            "invalid destination records blocked plan details");
         Assert
           (Archive.Localization.Text (Archive.Model.Notification_Key (Model)) =
              "Extraction blocked by the extraction plan.",
            "blocked extraction notification is localized precisely");
      end;

      Archive.Model.Select_Only (Model, 2);
      Archive.Model.Plan_Selected_Extraction (Model);
      declare
         Stale_FP : constant Archive.Source_Monitoring.Source_Fingerprint :=
           (Status => Archive.Source_Monitoring.Source_Missing,
            Size => 0,
            Modified_Time => Ada.Calendar.Time_Of (1970, 1, 1));
      begin
         Archive.Model.Set_Source_Fingerprint (Model, Stale_FP);
      end;

      declare
         Rejected : constant Archive.Extraction.Service.Extract_Result :=
           Archive.Extraction.Service.Extract_Planned
             (Model, Root & "/stale-out", Check_Identity => True);
      begin
         Assert (Rejected.Status = Archive.Extraction.Service.Extract_Source_Changed,
                 "extraction service rejects stale source fingerprint");
         Assert (not Ada.Directories.Exists (Root & "/stale-out/a.txt"),
                 "stale source rejection writes no output");
         Assert (Archive.Model.Extraction_Phase (Model) = Archive.Model.Extraction_Planned,
                 "failed extraction service keeps plan for retry");
         Assert (Archive.Model.Notification (Model) = Archive.Model.Error_Notification,
                 "failed extraction service publishes error notification");
         Assert
           (Archive.Model.Last_Extraction_Status (Model) =
              Archive.Extraction.Results.Failed_Write
            and then Archive.Model.Last_Extraction_Failed_Count (Model) = 1,
            "failed extraction service records failed write detail");
         Assert
           (Archive.Localization.Text (Archive.Model.Notification_Key (Model)) =
              "Extraction failed.",
            "failed extraction notification is localized");
      end;

      Archive.Model.Set_Source_Fingerprint
        (Model, Archive.Source_Monitoring.Fingerprint (Zip_Path));
      Archive.Model.Select_Only (Model, 2);
      Archive.Model.Plan_Selected_Extraction (Model);
      declare
         function Is_Cancelled return Boolean is
         begin
            return True;
         end Is_Cancelled;

         Cancelled_Result : constant Archive.Extraction.Service.Extract_Result :=
           Archive.Extraction.Service.Extract_Planned
             (Model, Root & "/cancelled-out",
              Cancelled => Is_Cancelled'Unrestricted_Access);
      begin
         Assert (Cancelled_Result.Status = Archive.Extraction.Service.Extract_Cancelled,
                 "extraction service reports cancellation");
         Assert (Cancelled_Result.Plan_Status = Archive.Extraction.Results.Execution_Cancelled,
                 "extraction service reports cancelled plan status");
         Assert (not Ada.Directories.Exists (Root & "/cancelled-out/a.txt"),
                 "cancelled extraction service writes no output");
         Assert (Archive.Model.Extraction_Phase (Model) = Archive.Model.No_Extraction,
                 "cancelled extraction service clears planned state");
         Assert (Archive.Model.Notification (Model) = Archive.Model.Warning_Notification,
                 "cancelled extraction service publishes warning notification");
         Assert
           (Archive.Model.Last_Extraction_Status (Model) = Archive.Extraction.Results.Cancelled
            and then Archive.Model.Last_Extraction_Plan_Status (Model) =
              Archive.Extraction.Results.Execution_Cancelled,
            "cancelled extraction service records cancelled execution detail");
         Assert
           (Archive.Localization.Text (Archive.Model.Notification_Key (Model)) =
              "Extraction cancelled.",
            "cancelled extraction notification is localized");
      end;

      declare
         Constrained_Settings : Archive.Settings.Settings_Model := Archive.Model.Effective_Settings (Model);
      begin
         Constrained_Settings.Per_Entry_Extraction_Limit := Archive.Resource_Limits.Limit_Value (2);
         Constrained_Settings.Total_Extraction_Limit := Archive.Resource_Limits.Limit_Value (100);
         Archive.Model.Apply_Settings (Model, Constrained_Settings);
      end;

      Archive.Model.Select_Only (Model, 2);
      Archive.Model.Plan_Selected_Extraction (Model);
      declare
         Limited_Result : constant Archive.Extraction.Service.Extract_Result :=
           Archive.Extraction.Service.Extract_Planned
             (Model, Root & "/limited-out");
      begin
         Assert (Limited_Result.Status = Archive.Extraction.Service.Extract_Publish_Failed,
                 "configured per-entry extraction limit fails through service");
         Assert
           (Limited_Result.Publish_Status = Archive.Extraction.Results.Failed_Limit,
            "configured per-entry limit reports typed publish status");
         Assert (not Ada.Directories.Exists (Root & "/limited-out/a.txt"),
                 "limit failure publishes no output");
         Assert
           (Archive.Model.Last_Extraction_Status (Model) = Archive.Extraction.Results.Failed_Limit,
            "configured limit failure is retained in model");
         Assert
           (Archive.Localization.Text (Archive.Model.Notification_Key (Model)) =
              "Extraction failed because an extraction limit was exceeded.",
            "configured limit failure notification is localized precisely");
      end;

      Archive.Model.Publish_Extraction_Result
        (Model,
         Success        => False,
         Plan_Status    => Archive.Extraction.Results.Execution_Failed,
         Publish_Status => Archive.Extraction.Results.Failed_Limit,
         Failed_Count   => 1);
      Assert
        (Archive.Model.Last_Extraction_Status (Model) = Archive.Extraction.Results.Failed_Limit,
         "model records extraction limit failures");
      Assert
        (Archive.Localization.Text (Archive.Model.Notification_Key (Model)) =
           "Extraction failed because an extraction limit was exceeded.",
         "limit extraction notification is localized precisely");
   end Test_Extraction_Service;

   procedure Test_Open_Workflow (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      Root         : constant String := "obj/open-workflow-test";
      Zip_Path     : constant String := Root & "/sample.zip";
      Tar_Path     : constant String := Root & "/sample.tar";
      Tar_Gz_Path  : constant String := Root & "/sample.tar.gz";
      Bad_Path     : constant String := Root & "/not-an-archive.zip";
      Missing_Path : constant String := Root & "/missing.zip";
      Model        : Archive.Model.Application_Model;

      function Entry_Id_For
        (Index : Archive.Archives.Index.Archive_Index;
         Path  : String)
         return Archive.Types.Entry_Id
      is
      begin
         for Raw_Id in 1 .. Archive.Archives.Index.Entry_Count (Index) loop
            declare
               Id   : constant Archive.Types.Entry_Id := Archive.Types.Entry_Id (Raw_Id);
               Item : constant Archive.Archives.Entries.Archive_Entry :=
                 Archive.Archives.Index.Entry_For (Index, Id);
            begin
               if To_String (Item.Original_Path) = Path then
                  return Id;
               end if;
            end;
         end loop;
         return Archive.Types.No_Entry;
      end Entry_Id_For;
   begin
      if not Ada.Directories.Exists (Root) then
         Ada.Directories.Create_Path (Root);
      end if;

      Write_Bytes (Zip_Path, One_File_Zip);
      Write_Bytes (Tar_Path, One_File_Tar);
      declare
         Status : Zlib.Status_Code;
         Tar_Gz : constant Zlib.Byte_Array := Zlib.GZip (One_File_Tar, Zlib.Fixed, Status);
      begin
         Assert (Status = Zlib.Ok, "tar.gz retained backing fixture compresses");
         Write_Bytes (Tar_Gz_Path, Tar_Gz);
      end;
      Write_Bytes
        (Bad_Path,
         [1 => Zlib.Byte (Character'Pos ('n')),
          2 => Zlib.Byte (Character'Pos ('o'))]);

      declare
         Streamed : constant Archive.Archives.Streams.Buffered_Source :=
           Archive.Archives.Streams.Read_Bounded (Zip_Path, Max_Bytes => 4096, Chunk_Size => 2);
         Over_Limit : constant Archive.Archives.Streams.Buffered_Source :=
           Archive.Archives.Streams.Read_Bounded (Zip_Path, Max_Bytes => 1, Chunk_Size => 1);
         Prefix : constant Archive.Archives.Streams.Buffered_Source :=
           Archive.Archives.Streams.Read_Prefix (Zip_Path, Max_Bytes => 4);
      begin
         Assert
           (Streamed.Status = Archive.Archives.Errors.Ok
            and then Byte_Length (Streamed) = One_File_Zip'Length,
            "source stream boundary reads archive bytes in bounded chunks");
         Assert
           (Over_Limit.Status = Archive.Archives.Errors.Limit_Exceeded
            and then Byte_Length (Over_Limit) = 0,
            "source stream boundary rejects reads that exceed the bound");
         Assert
           (Prefix.Status = Archive.Archives.Errors.Ok
            and then Byte_Length (Prefix) = 4,
            "source stream boundary can probe a prefix without materializing the file");
      end;

      declare
         Streamed_Tar : constant Archive.Archives.Opening.Prepared_Open_Result :=
           Archive.Archives.Opening.Prepare_Path (Tar_Path, Max_Bytes => 1);
      begin
         Assert (Streamed_Tar.Status = Archive.Archives.Opening.Open_Completed,
                 "open workflow streams tar files beyond byte-array open limit");
         Assert (Streamed_Tar.Format = Archive.Archives.Formats.Tar_Format,
                 "file-backed tar open publishes tar format");
      end;

      Archive.Model.Initialize (Model);
      declare
         Result : constant Archive.Archives.Opening.Open_Attempt_Result :=
           Archive.Archives.Opening.Open_Path (Model, Tar_Gz_Path);
         Backing : constant String := Archive.Model.Backing_Path (Model);
      begin
         Assert (Result.Status = Archive.Archives.Opening.Open_Completed,
                 "tar.gz open workflow completes through retained backing");
         Assert (Archive.Model.Published_Format (Model) = Archive.Archives.Formats.Tar_GZip_Format,
                 "tar.gz open workflow publishes tar.gz format");
         Assert (Backing /= "" and then Ada.Directories.Exists (Backing),
                 "tar.gz open workflow retains session-owned backing file");
         Assert (Archive.Model.Payload_Source_Path (Model) = Backing,
                 "tar.gz payload source resolves to retained backing");
         declare
            Payload_Id : constant Archive.Types.Entry_Id :=
              Entry_Id_For (Archive.Model.Published_Index (Model), "docs/readme.txt");
            Overlay : constant Archive.Verification.Overlays.Verification_Overlay :=
              Archive.Verification.Archives.Verify_All_File
                (Backing,
                 Tar_Gz_Path,
                 Archive.Model.Published_Index (Model),
                 Session   => Archive.Model.Session_Generation (Model),
                 Operation => 99);
         begin
            Assert (Payload_Id /= Archive.Types.No_Entry,
                    "tar.gz retained backing index exposes payload entry");
            Assert
              (Archive.Verification.Overlays.Integrity_For (Overlay, Payload_Id) =
                 Archive.Archives.Entries.Verified,
               "tar.gz verification reads payload from retained backing");
         end;
         Archive.Model.Close_Archive (Model);
         Assert (not Ada.Directories.Exists (Backing),
                 "closing tar.gz session cleans retained backing file");
      end;

      Archive.Model.Initialize (Model);
      declare
         Result : constant Archive.Archives.Opening.Open_Attempt_Result :=
           Archive.Archives.Opening.Open_Path (Model, Zip_Path);
      begin
         Assert (Result.Status = Archive.Archives.Opening.Open_Completed,
                 "open workflow completes for a valid zip archive");
         Assert (Result.Published and then Archive.Model.Has_Index (Model),
                 "open workflow publishes immutable index into model");
         Assert (Archive.Model.Source_Path (Model) = Zip_Path,
                 "open workflow records source path");
         Assert (Archive.Model.Published_Format (Model) = Archive.Archives.Formats.Zip_Format,
                 "open workflow publishes detected format");
         Assert (Archive.Model.Source_Fingerprint (Model).Status = Archive.Source_Monitoring.Source_Ready,
                 "open workflow records source fingerprint");
         Assert (Archive.Model.Lifecycle (Model) = Archive.Model.Archive_Ready,
                 "open workflow marks model ready after successful publication");
         Assert (Archive.Model.Has_Recent_Archives (Model),
                 "open workflow records successful source as recent archive");
         Assert
           (Natural (Archive.Model.Recent_Archives (Model).Length) = 1
            and then To_String (Archive.Model.Recent_Archives (Model).Element (1)) = Zip_Path,
            "open workflow exposes recent archives through model settings");
      end;

      declare
         Before_Generation : constant Archive.Types.Generation_Id := Archive.Model.Session_Generation (Model);
         Result : constant Archive.Archives.Opening.Open_Attempt_Result :=
           Archive.Archives.Opening.Open_Path (Model, Bad_Path);
      begin
         Assert (Result.Status = Archive.Archives.Opening.Open_Invalid_Format,
                 "open workflow rejects invalid archive bytes");
         Assert (Archive.Model.Session_Generation (Model) = Before_Generation,
                 "failed replacement open retains existing archive session generation");
         Assert (Archive.Model.Source_Path (Model) = Zip_Path,
                 "failed replacement open retains previous archive source");
         Assert (Natural (Archive.Model.Recent_Archives (Model).Length) = 1,
                 "failed replacement open does not add invalid recent archive");
      end;

      declare
         Result : constant Archive.Archives.Opening.Open_Attempt_Result :=
           Archive.Archives.Opening.Open_Path (Model, Missing_Path);
      begin
         Assert (Result.Status = Archive.Archives.Opening.Open_Source_Failed,
                 "open workflow rejects missing source files");
         Assert (Archive.Model.Source_Path (Model) = Zip_Path,
                 "missing replacement source retains previous archive");
         Assert (Natural (Archive.Model.Recent_Archives (Model).Length) = 1,
                 "missing replacement source does not add invalid recent archive");
      end;

      declare
         Result : constant Archive.Archives.Opening.Open_Attempt_Result :=
           Archive.Archives.Opening.Open_Path (Model, Zip_Path, Max_Bytes => 1);
      begin
         Assert (Result.Status = Archive.Archives.Opening.Open_Limit_Exceeded,
                 "open workflow rejects sources larger than the configured bound");
      end;

      declare
         Empty_Physical : Archive.Archives.Entries.Entry_Vectors.Vector;
         Build          : constant Archive.Archives.Index.Build_Result :=
           Archive.Archives.Index.Build (Empty_Physical);
         Operation      : constant Archive.Types.Generation_Id := Archive.Model.Begin_Open (Model);
         Newer          : constant Archive.Types.Generation_Id := Archive.Model.Begin_Open (Model);
         Accepted       : Boolean;
      begin
         pragma Unreferenced (Newer);
         Accepted :=
           Archive.Model.Publish_Open_Result
             (Model, Operation, "stale.zip", Archive.Source_Monitoring.Fingerprint (Zip_Path),
              Build.Index, Archive.Archives.Formats.Zip_Format, Success => True);
         Assert (not Accepted, "model rejects stale open completions");
         Assert (Archive.Model.Source_Path (Model) = Zip_Path,
                 "stale open completion cannot replace current archive");
      end;
   end Test_Open_Workflow;

   procedure Test_Open_Task (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      Root      : constant String := "obj/open-task-test";
      Zip_Path  : constant String := Root & "/sample.zip";
      Model     : Archive.Model.Application_Model;
      Bridge    : aliased Archive.Tasking.Services.Event_Bridge (Capacity => 4);
      Results   : aliased Archive.Archives.Opening.Tasks.Result_Box;
      Operation : Archive.Types.Generation_Id;
   begin
      if not Ada.Directories.Exists (Root) then
         Ada.Directories.Create_Path (Root);
      end if;
      Write_Bytes (Zip_Path, One_File_Zip);

      Archive.Model.Initialize (Model);
      Operation := Archive.Model.Begin_Open (Model);
      Bridge.Configure
        ((Current_Session      => Archive.Model.Session_Generation (Model),
          Current_Open         => Operation,
          Current_Preview      => Archive.Types.No_Generation,
          Current_Verification => Archive.Types.No_Generation,
          Current_Extraction   => Archive.Types.No_Generation,
          Current_Save         => Archive.Types.No_Generation,
          Current_Source_Watch => Archive.Types.No_Generation,
          Shutting_Down        => False));

      declare
         Worker : Archive.Archives.Opening.Tasks.Open_Worker;
      begin
         Worker.Start
           (Path           => Zip_Path,
            Session        => Archive.Model.Session_Generation (Model),
            Operation      => Operation,
            Max_Bytes      => Archive.Archives.Opening.Default_Max_Open_Bytes,
            Check_Identity => True,
            Bridge         => Bridge'Unchecked_Access,
            Results        => Results'Unchecked_Access);

         declare
            Prepared_Operation : Archive.Types.Generation_Id;
            Prepared           : Archive.Archives.Opening.Prepared_Open_Result;
            Event              : Archive.Tasking.Events.Event;
            Found              : Boolean := False;
         begin
            Results.Wait (Prepared_Operation, Prepared);
            Bridge.Dequeue (Event, Found);
            Assert
              (Found
               and then Event.Kind = Archive.Tasking.Events.Open_Completed
               and then Event.Operation_Generation = Operation,
               "open worker publishes an open-completed event through the bridge");
            Assert
              (Prepared_Operation = Operation
               and then Prepared.Status = Archive.Archives.Opening.Open_Completed,
               "open worker stores a prepared open result without mutating the model");
            Assert (not Archive.Model.Has_Index (Model),
                    "open worker does not publish directly into the model");

            declare
               Applied : constant Archive.Archives.Opening.Open_Attempt_Result :=
                 Archive.Archives.Opening.Publish_Prepared
                   (Model, Prepared_Operation, Zip_Path, Prepared);
            begin
               Assert (Applied.Published and then Archive.Model.Has_Index (Model),
                       "main thread publishes prepared open result into the model");
            end;
         end;
      end;

      declare
         Old_Event : constant Archive.Tasking.Events.Event :=
           (Kind                 => Archive.Tasking.Events.Open_Completed,
            Session_Generation   => Archive.Model.Session_Generation (Model),
            Operation_Generation => Operation,
            Progress_Numerator   => 0,
            Progress_Denominator => 0);
      begin
         Assert
           (Archive.Tasking.Events.Classify
              (Old_Event,
               Current_Session   => Archive.Model.Session_Generation (Model),
               Current_Operation => Operation + 1) = Archive.Tasking.Events.Reject_Stale_Event,
            "open completion events are rejected when the open generation is stale");
      end;
   end Test_Open_Task;

   procedure Test_Open_Coordinator (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      Root        : constant String := "obj/open-coordinator-test";
      Zip_Path    : constant String := Root & "/sample.zip";
      Model       : Archive.Model.Application_Model;
      Coordinator : Archive.Operations.Opening.Coordinator;
      Result      : Archive.Operations.Opening.Drain_Result;
   begin
      if not Ada.Directories.Exists (Root) then
         Ada.Directories.Create_Path (Root);
      end if;
      Write_Bytes (Zip_Path, One_File_Zip);

      Archive.Model.Initialize (Model);
      Archive.Operations.Opening.Start_Open (Coordinator, Model, Zip_Path);
      Assert (Archive.Operations.Opening.Active (Coordinator),
              "open coordinator enters running state after start");
      Assert (Archive.Model.Lifecycle (Model) = Archive.Model.Opening_Archive,
              "open coordinator starts a model open generation");

      for Attempt in 1 .. 100_000 loop
         Archive.Operations.Opening.Drain_Events (Coordinator, Model, Result);
         exit when Result.Event_Seen;
      end loop;

      Assert (Result.Event_Seen and then Result.Applied,
              "open coordinator drains worker event and applies prepared result");
      Assert (Result.Status = Archive.Operations.Opening.Operation_Completed,
              "open coordinator records completed operation status");
      Assert (Result.Open_Status = Archive.Archives.Opening.Open_Completed,
              "open coordinator exposes successful open status");
      Assert (Result.Wakeup_Acknowledged,
              "open coordinator acknowledges the bridge wakeup after draining");
      Assert (Archive.Model.Has_Index (Model)
              and then Archive.Model.Source_Path (Model) = Zip_Path,
              "open coordinator publishes the archive index into the model");
      Assert (not Archive.Operations.Opening.Active (Coordinator),
              "open coordinator leaves running state after completion");
      Assert
        (Archive.Operations.Opening.Current_Operation (Coordinator) =
         Archive.Model.Current_Open_Generation (Model),
         "open coordinator operation id matches model open generation");
   end Test_Open_Coordinator;

   procedure Test_Source_Monitoring (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      Dir  : constant String := "obj/source-monitoring-test";
      Path : constant String := Dir & "/sample.bin";
      Zip  : constant Zlib.Byte_Array := [1 => 16#50#, 2 => 16#4B#, 3 => 16#03#, 4 => 16#04#];
      Gz   : constant Zlib.Byte_Array := [1 => 16#1F#, 2 => 16#8B#, 3 => 16#08#, 4 => 16#00#];
   begin
      if not Ada.Directories.Exists (Dir) then
         Ada.Directories.Create_Path (Dir);
      end if;

      Write_Bytes (Path, Zip);
      declare
         FP1 : constant Archive.Source_Monitoring.Source_Fingerprint :=
           Archive.Source_Monitoring.Fingerprint (Path);
         Probe : constant Archive.Source_Monitoring.Probe_Result :=
           Archive.Source_Monitoring.Probe (Path, Limit => 2);
         Detection : constant Archive.Archives.Formats.Detection_Result :=
           Archive.Source_Monitoring.Detect_File (Path);
      begin
         Assert (FP1.Status = Archive.Source_Monitoring.Source_Ready, "regular file fingerprinted");
         Assert (Probe.Status = Archive.Source_Monitoring.Source_Ready, "regular file probed");
         Assert (Byte_Length (Probe) = 2, "probe respects caller limit");
         Assert (Detection.Format = Archive.Archives.Formats.Zip_Format, "probe detects zip");

         delay 0.02;
         Write_Bytes (Path, Gz);
         declare
            FP2 : constant Archive.Source_Monitoring.Source_Fingerprint :=
              Archive.Source_Monitoring.Fingerprint (Path);
            Detection2 : constant Archive.Archives.Formats.Detection_Result :=
              Archive.Source_Monitoring.Detect_File (Path);
         begin
            Assert (not Archive.Source_Monitoring.Same_Source (FP1, FP2),
                    "source replacement changes fingerprint");
            Assert (Detection2.Format = Archive.Archives.Formats.GZip_Format, "replacement detects gzip");
         end;
      end;

      declare
         Model    : Archive.Model.Application_Model;
         Physical : Archive.Archives.Entries.Entry_Vectors.Vector;
         Config   : constant Archive.UI.Shell_Configuration :=
           (Width => 1024,
            Height => 720,
            Locale => To_Unbounded_String ("en"),
            Line_Height => 20);
      begin
         Physical.Append (Fixture_Entry ("payload.txt"));
         declare
            Build : constant Archive.Archives.Index.Build_Result :=
              Archive.Archives.Index.Build (Physical);
            Initial : constant Archive.Source_Monitoring.Source_Fingerprint :=
              Archive.Source_Monitoring.Fingerprint (Path);
         begin
            Archive.Model.Initialize (Model);
            Archive.Model.Publish_Archive_Index
              (Model, Path, Build.Index, Archive.Archives.Formats.Zip_Format);
            Archive.Model.Set_Source_Fingerprint (Model, Initial);
            Archive.Model.Select_Only (Model, 2);
            Archive.Model.Plan_Selected_Extraction (Model);
            Archive.Model.Start_Preview (Model, 2);
            Archive.Model.Start_Verification (Model);

            Assert
              (Archive.Model.Observe_Source_Fingerprint (Model, Initial) =
                 Archive.Model.Source_Unchanged,
               "unchanged source watch records unchanged state");
            Assert
              (Archive.Model.Last_Source_Change (Model) = Archive.Model.Source_Unchanged,
               "model retains unchanged source-watch state");

            delay 0.02;
            Write_Bytes
              (Path,
               [1 => 16#50#, 2 => 16#4B#, 3 => 16#05#, 4 => 16#06#]);

            declare
               Updated : constant Archive.Source_Monitoring.Source_Fingerprint :=
                 Archive.Source_Monitoring.Fingerprint (Path);
               Decision : constant Archive.Model.Source_Change_State :=
                 Archive.Model.Observe_Source_Fingerprint (Model, Updated);
               Shell : constant Archive.UI.Shell_Snapshot :=
                 Archive.UI.Build_Shell (Model, Config);
            begin
               Assert (Decision = Archive.Model.Source_Modified,
                       "modified source watch reports source modification");
               Assert (Archive.Model.Lifecycle (Model) = Archive.Model.Archive_Warnings,
                       "modified source watch moves model to warning lifecycle");
               Assert (Archive.Model.Extraction_Phase (Model) = Archive.Model.No_Extraction,
                       "modified source watch clears stale extraction plan");
               Assert (Archive.Model.Preview_Phase (Model) = Archive.Model.Preview_Failed,
                       "modified source watch rejects stale preview state");
               Assert
                 (Archive.Model.Verification_Phase (Model) =
                    Archive.Verification.Overlays.Verification_Not_Run,
                  "modified source watch clears verification overlay");
               Assert
                 (Archive.Localization.Text (Archive.Model.Notification_Key (Model)) =
                    "Archive source changed. Reload before reading entries.",
                  "modified source notification is localized");
               Assert (Shell.Source.Change = Archive.Model.Source_Modified,
                       "ui source snapshot exposes source-change state");
            end;

            declare
               Missing : constant Archive.Source_Monitoring.Source_Fingerprint :=
                 (Status => Archive.Source_Monitoring.Source_Missing,
                  Size => 0,
                  Modified_Time => Ada.Calendar.Time_Of (1970, 1, 1));
            begin
               Assert
                 (Archive.Model.Observe_Source_Fingerprint (Model, Missing) =
                    Archive.Model.Source_Unavailable,
                  "missing source watch reports source unavailable");
            end;
         end;
      end;
   end Test_Source_Monitoring;

   procedure Test_Stale_Events (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      Current_Session : constant Archive.Types.Generation_Id := 10;
      Current_Op      : constant Archive.Types.Generation_Id := 20;
      Current : constant Archive.Tasking.Events.Event :=
        (Kind => Archive.Tasking.Events.Preview_Completed,
         Session_Generation => Current_Session,
         Operation_Generation => Current_Op,
         Progress_Numerator => 0,
         Progress_Denominator => 0);
      Old_Session : constant Archive.Tasking.Events.Event :=
        (Kind => Archive.Tasking.Events.Preview_Completed,
         Session_Generation => Current_Session - 1,
         Operation_Generation => Current_Op,
         Progress_Numerator => 0,
         Progress_Denominator => 0);
      Old_Op : constant Archive.Tasking.Events.Event :=
        (Kind => Archive.Tasking.Events.Extraction_Progress,
         Session_Generation => Current_Session,
         Operation_Generation => Current_Op - 1,
         Progress_Numerator => 1,
         Progress_Denominator => 2);
      Shutdown : constant Archive.Tasking.Events.Event :=
        (Kind => Archive.Tasking.Events.Shutdown,
         Session_Generation => 0,
         Operation_Generation => 0,
         Progress_Numerator => 0,
         Progress_Denominator => 0);
   begin
      Assert
        (Archive.Tasking.Events.Classify (Current, Current_Session, Current_Op)
         = Archive.Tasking.Events.Accept_Event,
         "current event accepted");
      Assert
        (Archive.Tasking.Events.Classify (Old_Session, Current_Session, Current_Op)
         = Archive.Tasking.Events.Reject_Stale_Event,
         "old session event rejected");
      Assert
        (Archive.Tasking.Events.Classify (Old_Op, Current_Session, Current_Op)
         = Archive.Tasking.Events.Reject_Stale_Event,
         "old operation event rejected");
      Assert
        (Archive.Tasking.Events.Classify (Shutdown, Current_Session, Current_Op)
         = Archive.Tasking.Events.Accept_Event,
         "shutdown event is never stale-displaced");
   end Test_Stale_Events;

   procedure Test_Entry_Verification (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      Zip_Bytes : constant Zlib.Byte_Array := One_File_Zip;
      Gz_Status : Zlib.Status_Code;
      Plain : constant Zlib.Byte_Array :=
        [1 => Zlib.Byte (Character'Pos ('a')),
         2 => Zlib.Byte (Character'Pos ('b')),
         3 => Zlib.Byte (Character'Pos ('c'))];
      Gz : constant Zlib.Byte_Array := Zlib.GZip (Plain, Zlib.Fixed, Gz_Status);
   begin
      declare
         Path : constant String := "obj/verification-streaming-test/sample.zip";
         Opened : constant Archive.Archives.Readers.Dispatch.Open_Result :=
           Open_Dispatch (Zip_Bytes, Source_Name => "sample.zip");
         Item : constant Archive.Archives.Entries.Archive_Entry :=
           Archive.Archives.Index.Entry_For (Opened.Index, 2);
      begin
         Ada.Directories.Create_Path ("obj/verification-streaming-test");
         Write_Bytes (Path, Zip_Bytes);
         declare
            Result : constant Archive.Verification.Entries.Entry_Verification_Result :=
              Archive.Verification.Entries.Verify_File (Path, "sample.zip", Item);
         begin
            Assert (Opened.Status = Archive.Archives.Errors.Ok, "verification zip fixture opens");
            Assert
              (Result.Status = Archive.Archives.Errors.Ok
               and then Result.Integrity = Archive.Archives.Entries.Verified,
               "entry verification accepts valid zip payload");
         end;
      end;

      declare
         Bad : constant Zlib.Byte_Array := One_File_Zip (Bad_CRC => True);
         Path : constant String := "obj/verification-streaming-test/bad.zip";
         Opened : constant Archive.Archives.Readers.Dispatch.Open_Result :=
           Open_Dispatch (Bad, Source_Name => "bad.zip");
         Item : constant Archive.Archives.Entries.Archive_Entry :=
           Archive.Archives.Index.Entry_For (Opened.Index, 2);
      begin
         Ada.Directories.Create_Path ("obj/verification-streaming-test");
         Write_Bytes (Path, Bad);
         declare
            Result : constant Archive.Verification.Entries.Entry_Verification_Result :=
              Archive.Verification.Entries.Verify_File (Path, "bad.zip", Item);
         begin
            Assert (Opened.Status = Archive.Archives.Errors.Ok, "bad crc zip fixture still indexes");
            Assert
              (Result.Status = Archive.Archives.Errors.Invalid_Format
               and then Result.Integrity = Archive.Archives.Entries.Failed,
               "entry verification rejects bad zip crc");
         end;
      end;

      declare
         Path : constant String := "obj/verification-streaming-test/sample.txt.gz";
         Opened : constant Archive.Archives.Readers.Dispatch.Open_Result :=
           Open_Dispatch (Gz, Source_Name => "sample.txt.gz");
         Item : constant Archive.Archives.Entries.Archive_Entry :=
           Archive.Archives.Index.Entry_For (Opened.Index, 2);
      begin
         Ada.Directories.Create_Path ("obj/verification-streaming-test");
         Write_Bytes (Path, Gz);
         declare
            Result : constant Archive.Verification.Entries.Entry_Verification_Result :=
              Archive.Verification.Entries.Verify_File (Path, "sample.txt.gz", Item);
         begin
            Assert (Gz_Status = Zlib.Ok, "verification gzip fixture builds");
            Assert (Opened.Status = Archive.Archives.Errors.Ok, "verification gzip fixture opens");
            Assert
              (Result.Status = Archive.Archives.Errors.Ok
               and then Result.Integrity = Archive.Archives.Entries.Verified,
               "entry verification accepts valid gzip payload");
         end;
      end;

      declare
         Root : constant String := "obj/verification-streaming-test";
         Path : constant String := Root & "/large.zip";
         Big : Zlib.Byte_Array (1 .. 70_000);
      begin
         Ada.Directories.Create_Path (Root);
         for Index in Big'Range loop
            Big (Index) := Zlib.Byte (Index mod 251);
         end loop;
         Write_Bytes (Path, Stored_Zip_With_Payload (Big, Method => 8));

         declare
            Opened : constant Archive.Archives.Readers.Dispatch.Open_Result :=
              Archive.Archives.Readers.Dispatch.Open_File (Path, Source_Name => "large.zip");
            Item : constant Archive.Archives.Entries.Archive_Entry :=
              Archive.Archives.Index.Entry_For (Opened.Index, 2);
            Result : constant Archive.Verification.Entries.Entry_Verification_Result :=
              Archive.Verification.Entries.Verify_File (Path, "large.zip", Item);
         begin
            Assert (Opened.Status = Archive.Archives.Errors.Ok,
                    "streaming verification zip fixture opens from file");
            Assert (Item.Method = Archive.Archives.Entries.Zip_Deflate,
                    "streaming verification uses deflated zip entry");
            Assert
              (Result.Status = Archive.Archives.Errors.Ok
               and then Result.Integrity = Archive.Archives.Entries.Verified,
               "file-backed entry verification streams large deflated zip payload");
         end;
      end;
   end Test_Entry_Verification;

   procedure Test_Full_Archive_Verification (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      Bytes : constant Zlib.Byte_Array := One_File_Zip;
      Path  : constant String := "obj/full-verification-streaming-test/sample.zip";
      Opened : constant Archive.Archives.Readers.Dispatch.Open_Result :=
        Open_Dispatch (Bytes, Source_Name => "sample.zip");
      Model : Archive.Model.Application_Model;
   begin
      Ada.Directories.Create_Path ("obj/full-verification-streaming-test");
      Write_Bytes (Path, Bytes);
      declare
         Overlay : constant Archive.Verification.Overlays.Verification_Overlay :=
           Archive.Verification.Archives.Verify_All_File
             (Path, "sample.zip", Opened.Index, Session => 4, Operation => 8);
      begin
         Assert (Opened.Status = Archive.Archives.Errors.Ok, "full verification fixture opens");
         Assert
           (Archive.Verification.Overlays.Entry_Count (Overlay) = 1,
            "full verification stores one physical regular-file result");
         Assert
           (Archive.Verification.Overlays.Integrity_For (Overlay, 2) =
              Archive.Archives.Entries.Verified,
            "full verification marks valid payload verified");

         Archive.Model.Initialize (Model);
         Archive.Model.Publish_Archive (Model, "sample.zip");
         Archive.Model.Start_Verification (Model);
         Assert
           (Archive.Model.Publish_Verification (Model, Overlay) =
            Archive.Verification.Overlays.Overlay_Rejected_Stale,
            "model rejects full verification overlay with stale generations");
      end;

      declare
         Root : constant String := "obj/full-verification-streaming-test";
         Path : constant String := Root & "/large.zip";
         Big : Zlib.Byte_Array (1 .. 70_000);
      begin
         Ada.Directories.Create_Path (Root);
         for Index in Big'Range loop
            Big (Index) := Zlib.Byte ((Index * 3) mod 251);
         end loop;
         Write_Bytes (Path, Stored_Zip_With_Payload (Big, Method => 8));

         declare
            Opened_File : constant Archive.Archives.Readers.Dispatch.Open_Result :=
              Archive.Archives.Readers.Dispatch.Open_File (Path, Source_Name => "large.zip");
            File_Overlay : constant Archive.Verification.Overlays.Verification_Overlay :=
              Archive.Verification.Archives.Verify_All_File
                (Path, "large.zip", Opened_File.Index, Session => 7, Operation => 11);
         begin
            Assert (Opened_File.Status = Archive.Archives.Errors.Ok,
                    "file-backed full verification fixture opens");
            Assert
              (Archive.Verification.Overlays.Entry_Count (File_Overlay) = 1,
               "file-backed full verification stores one result");
            Assert
              (Archive.Verification.Overlays.Integrity_For (File_Overlay, 2) =
                 Archive.Archives.Entries.Verified,
               "file-backed full verification streams large deflated payload");
         end;
      end;
   end Test_Full_Archive_Verification;

   procedure Test_Verification_Overlay (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      Overlay : Archive.Verification.Overlays.Verification_Overlay :=
        Archive.Verification.Overlays.Empty (Session => 5, Operation => 9);
      Old_Session : constant Archive.Verification.Overlays.Verification_Overlay :=
        Archive.Verification.Overlays.Empty (Session => 4, Operation => 9);
      Old_Operation : constant Archive.Verification.Overlays.Verification_Overlay :=
        Archive.Verification.Overlays.Empty (Session => 5, Operation => 8);
      Cancelled : constant Archive.Verification.Overlays.Verification_Overlay :=
        Archive.Verification.Overlays.Empty
          (Session => 5, Operation => 9,
           Phase => Archive.Verification.Overlays.Verification_Cancelled);
   begin
      Assert
        (Archive.Verification.Overlays.Session_Generation (Overlay) = 5
         and then Archive.Verification.Overlays.Operation_Generation (Overlay) = 9,
         "overlay records generations");
      Assert
        (Archive.Verification.Overlays.Phase (Overlay) =
           Archive.Verification.Overlays.Verification_Running,
         "overlay records phase");

      Archive.Verification.Overlays.Set_Result
        (Overlay, 10, Archive.Archives.Entries.Verified, "verification.ok");
      Archive.Verification.Overlays.Set_Result
        (Overlay, 11, Archive.Archives.Entries.Failed, "verification.crc_failed");
      Assert (Archive.Verification.Overlays.Entry_Count (Overlay) = 2, "overlay stores entry results");
      Assert (Archive.Verification.Overlays.Contains (Overlay, 10), "overlay lookup finds stored entry");
      Assert
        (Archive.Verification.Overlays.Integrity_For (Overlay, 10) =
           Archive.Archives.Entries.Verified,
         "overlay returns stored integrity");
      Assert
        (Archive.Verification.Overlays.Integrity_For (Overlay, 12) =
           Archive.Archives.Entries.Not_Checked,
         "missing overlay result remains not checked");

      Archive.Verification.Overlays.Set_Result
        (Overlay, 10, Archive.Archives.Entries.Failed, "verification.changed");
      Assert
        (Archive.Verification.Overlays.Entry_Count (Overlay) = 2
         and then Archive.Verification.Overlays.Integrity_For (Overlay, 10) =
           Archive.Archives.Entries.Failed,
         "setting the same entry replaces without duplicating");

      Assert
        (Archive.Verification.Overlays.Accept_Result
           (Overlay, Current_Session => 5, Current_Verification => 9) =
         Archive.Verification.Overlays.Overlay_Accepted,
         "current verification overlay accepted");
      Assert
        (Archive.Verification.Overlays.Accept_Result
           (Old_Session, Current_Session => 5, Current_Verification => 9) =
         Archive.Verification.Overlays.Overlay_Rejected_Stale,
         "old session verification overlay rejected");
      Assert
        (Archive.Verification.Overlays.Accept_Result
           (Old_Operation, Current_Session => 5, Current_Verification => 9) =
         Archive.Verification.Overlays.Overlay_Rejected_Stale,
         "old operation verification overlay rejected");
      Assert
        (Archive.Verification.Overlays.Accept_Result
           (Cancelled, Current_Session => 5, Current_Verification => 9) =
         Archive.Verification.Overlays.Overlay_Rejected_Cancelled,
         "cancelled verification overlay rejected");
   end Test_Verification_Overlay;

   procedure Test_Cancellation (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      Token : Archive.Tasking.Cancellation.Token;
   begin
      Assert (not Token.Cancelled, "token starts not cancelled");
      Token.Cancel;
      Assert (Token.Cancelled, "token records cancellation");
      Token.Cancel;
      Assert (Token.Cancelled, "token cancellation is idempotent");
      Token.Reset;
      Assert (not Token.Cancelled, "token reset clears cancellation");
   end Test_Cancellation;

   procedure Test_Bounded_Event_Queue (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      Queue : Archive.Tasking.Queues.Event_Queue (Capacity => 2);
      Result : Archive.Tasking.Queues.Enqueue_Result;
      Item : Archive.Tasking.Events.Event;
      Found : Boolean;
      Progress : constant Archive.Tasking.Events.Event :=
        (Kind => Archive.Tasking.Events.Extraction_Progress,
         Session_Generation => 1,
         Operation_Generation => 1,
         Progress_Numerator => 1,
         Progress_Denominator => 10);
      Terminal : constant Archive.Tasking.Events.Event :=
        (Kind => Archive.Tasking.Events.Extraction_Completed,
         Session_Generation => 1,
         Operation_Generation => 1,
         Progress_Numerator => 10,
         Progress_Denominator => 10);
      Shutdown : constant Archive.Tasking.Events.Event :=
        (Kind => Archive.Tasking.Events.Shutdown,
         Session_Generation => 0,
         Operation_Generation => 0,
         Progress_Numerator => 0,
         Progress_Denominator => 0);
   begin
      Queue.Enqueue (Progress, Result);
      Assert (Result = Archive.Tasking.Queues.Enqueued, "first progress enqueued");
      Queue.Enqueue (Progress, Result);
      Assert (Result = Archive.Tasking.Queues.Enqueued, "second progress enqueued");
      Assert (Queue.Is_Full, "queue is full at capacity");

      Queue.Enqueue (Progress, Result);
      Assert (Result = Archive.Tasking.Queues.Rejected_Full, "progress cannot displace progress");

      Queue.Enqueue (Terminal, Result);
      Assert (Result = Archive.Tasking.Queues.Enqueued, "terminal displaces progress");
      Assert (Queue.Count = 2, "terminal displacement preserves bounded count");

      declare
         Snapshot : constant Archive.Tasking.Queues.Queue_Policy_Snapshot := Queue.Snapshot;
      begin
         Assert (Snapshot.Count = 2, "queue snapshot records bounded count");
         Assert (Snapshot.Terminal_Count = 1 and then Snapshot.Progress_Count = 1,
                 "queue snapshot classifies terminal and progress entries");
         Assert (Snapshot.Displaced_Progress = 1,
                 "queue snapshot records progress displaced by terminal result");
         Assert (Snapshot.Rejected_Progress = 1,
                 "queue snapshot records rejected progress under saturation");
      end;

      Queue.Dequeue (Item, Found);
      Assert (Found, "dequeue finds first item");
      Queue.Dequeue (Item, Found);
      Assert (Found, "dequeue finds terminal item");
      Assert (Item.Kind = Archive.Tasking.Events.Extraction_Completed,
              "terminal result preserved in queue");

      Queue.Enqueue (Shutdown, Result);
      Assert (Result = Archive.Tasking.Queues.Enqueued, "shutdown enqueued when space exists");
   end Test_Bounded_Event_Queue;

   procedure Test_Tasking_Service_Bridge (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      Bridge : Archive.Tasking.Services.Event_Bridge (Capacity => 2);
      Result : Archive.Tasking.Services.Publish_Result;
      Item   : Archive.Tasking.Events.Event;
      Found  : Boolean;
      State  : constant Archive.Tasking.Services.Bridge_State :=
        (Current_Session      => 10,
         Current_Open         => 11,
         Current_Preview      => 12,
         Current_Verification => 13,
         Current_Extraction   => 14,
         Current_Save         => 15,
         Current_Source_Watch => 16,
         Shutting_Down        => False);
      Progress_1 : constant Archive.Tasking.Events.Event :=
        (Kind                 => Archive.Tasking.Events.Extraction_Progress,
         Session_Generation   => 10,
         Operation_Generation => 14,
         Progress_Numerator   => 1,
         Progress_Denominator => 4);
      Progress_2 : constant Archive.Tasking.Events.Event :=
        (Kind                 => Archive.Tasking.Events.Extraction_Progress,
         Session_Generation   => 10,
         Operation_Generation => 14,
         Progress_Numerator   => 3,
         Progress_Denominator => 4);
      Terminal : constant Archive.Tasking.Events.Event :=
        (Kind                 => Archive.Tasking.Events.Extraction_Completed,
         Session_Generation   => 10,
         Operation_Generation => 14,
         Progress_Numerator   => 4,
         Progress_Denominator => 4);
      Stale_Preview : constant Archive.Tasking.Events.Event :=
        (Kind                 => Archive.Tasking.Events.Preview_Completed,
         Session_Generation   => 10,
         Operation_Generation => 11,
         Progress_Numerator   => 0,
         Progress_Denominator => 0);
      Save_Done : constant Archive.Tasking.Events.Event :=
        (Kind                 => Archive.Tasking.Events.Save_Completed,
         Session_Generation   => 10,
         Operation_Generation => 15,
         Progress_Numerator   => 0,
         Progress_Denominator => 0);
      Stale_Save : constant Archive.Tasking.Events.Event :=
        (Kind                 => Archive.Tasking.Events.Save_Completed,
         Session_Generation   => 10,
         Operation_Generation => 14,
         Progress_Numerator   => 0,
         Progress_Denominator => 0);
      Source_Event : constant Archive.Tasking.Events.Event :=
        (Kind                 => Archive.Tasking.Events.Source_Changed,
         Session_Generation   => 10,
         Operation_Generation => 16,
         Progress_Numerator   => 0,
         Progress_Denominator => 0);
   begin
      Bridge.Configure (State);

      Bridge.Publish (Progress_1, Result);
      Assert (Result.Accepted and then Result.Wakeup_Requested,
              "first progress accepts and requests a main-thread wakeup");
      Assert (Bridge.Queue_Count = 0, "progress is coalesced outside the ordinary queue");
      Assert (Bridge.Wakeup_Pending, "bridge tracks pending wakeup until acknowledged");

      Bridge.Publish (Progress_2, Result);
      Assert
        (Result.Accepted and then Result.Coalesced and then not Result.Wakeup_Requested,
         "new progress replaces latest progress without producing another wakeup");
      Bridge.Take_Latest_Progress (Item, Found);
      Assert
        (Found
         and then Item.Progress_Numerator = 3
         and then Item.Progress_Denominator = 4,
         "main thread receives only the latest progress value");

      Bridge.Publish (Terminal, Result);
      Assert (Result.Accepted and then not Result.Wakeup_Requested,
              "terminal result enqueues while wakeup is already pending");
      declare
         Snapshot : constant Archive.Tasking.Services.Supervision_Snapshot := Bridge.Snapshot;
      begin
         Assert (Snapshot.Last_Accepted_Owner = Archive.Tasking.Services.Extraction_Owner,
                 "bridge supervision records extraction as current accepted owner");
         Assert (Snapshot.Latest_Progress_Ready = False,
                 "bridge supervision records drained progress slot");
         Assert (Snapshot.Queue.Terminal_Count = 1,
                 "bridge supervision exposes ordinary queue policy state");
      end;
      Bridge.Dequeue (Item, Found);
      Assert
        (Found and then Item.Kind = Archive.Tasking.Events.Extraction_Completed,
         "terminal result is retained for the main thread");

      Bridge.Publish (Save_Done, Result);
      Assert (Result.Accepted and then not Result.Stale,
              "bridge accepts current save completion event");
      declare
         Snapshot : constant Archive.Tasking.Services.Supervision_Snapshot := Bridge.Snapshot;
      begin
         Assert (Snapshot.Last_Accepted_Owner = Archive.Tasking.Services.Save_Owner,
                 "bridge supervision records save owner");
         Assert (Snapshot.State.Current_Save = 15,
                 "bridge supervision retains active save generation");
      end;
      Bridge.Dequeue (Item, Found);
      Assert (Found and then Item.Kind = Archive.Tasking.Events.Save_Completed,
              "save completion is queued for the main thread");

      Bridge.Publish (Source_Event, Result);
      Assert (Result.Accepted, "bridge accepts current source-watch event");
      declare
         Snapshot : constant Archive.Tasking.Services.Supervision_Snapshot := Bridge.Snapshot;
      begin
         Assert (Snapshot.Last_Accepted_Owner = Archive.Tasking.Services.Source_Watch_Owner,
                 "bridge supervision records source-watch owner");
      end;
      Bridge.Dequeue (Item, Found);
      Assert (Found and then Item.Kind = Archive.Tasking.Events.Source_Changed,
              "source-watch event is queued for the main thread");

      Bridge.Publish (Stale_Preview, Result);
      Assert (Result.Stale and then not Result.Accepted,
              "bridge rejects stale operation completion before queueing");
      Assert (Bridge.Rejected_Stale_Count = 1, "bridge records stale rejection diagnostics");
      Bridge.Publish (Stale_Save, Result);
      Assert (Result.Stale and then not Result.Accepted,
              "bridge rejects stale save completion before queueing");
      declare
         Snapshot : constant Archive.Tasking.Services.Supervision_Snapshot := Bridge.Snapshot;
      begin
         Assert (Snapshot.Last_Rejected_Owner = Archive.Tasking.Services.Save_Owner,
                 "bridge supervision records rejected save owner");
         Assert (Snapshot.Rejected_Stale_Count = 2,
                 "bridge supervision counts stale preview and save events");
      end;

      Bridge.Acknowledge_Wakeup;
      Assert (not Bridge.Wakeup_Pending, "main thread can acknowledge a coalesced wakeup");
      Bridge.Begin_Shutdown;
      Assert (Bridge.Wakeup_Pending, "shutdown requests a main-thread wakeup");
      Bridge.Dequeue (Item, Found);
      Assert
        (Found and then Item.Kind = Archive.Tasking.Events.Shutdown,
         "shutdown event is queued as a terminal control event");
      Bridge.Publish (Progress_1, Result);
      Assert (Result.Stale and then not Result.Accepted,
              "bridge rejects ordinary worker events after shutdown begins");
      Assert (Bridge.Accepted_Count = 6,
              "accepted counter covers progress, terminal, save, source, and shutdown events");
   end Test_Tasking_Service_Bridge;

   procedure Test_Temporary_Resources (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      Registry : Archive.Temporary_Resources.Registry (Capacity => 2);
      Id1      : Archive.Temporary_Resources.Resource_Id;
      Id2      : Archive.Temporary_Resources.Resource_Id;
      Id3      : Archive.Temporary_Resources.Resource_Id;
      Stored   : Boolean;
      Decision : Archive.Temporary_Resources.Cleanup_Decision;
      Fresh    : constant String :=
        Archive.Temporary_Resources.Fresh_Sibling_Path
          ("/tmp/archive", "/tmp/archive/session/file", "tmp");
   begin
      Assert
        (Archive.Temporary_Resources.Under_Root ("/tmp/archive", "/tmp/archive/session/file"),
         "child path is under temp root");
      Assert
        (not Archive.Temporary_Resources.Under_Root ("/tmp/archive", "/tmp/archive-evil/file"),
         "prefix sibling is not under temp root");
      Assert
        (Fresh /= ""
         and then Fresh /= "/tmp/archive/session/file"
         and then Archive.Temporary_Resources.Under_Root ("/tmp/archive", Fresh),
         "fresh sibling temp path is contained and distinct");

      Registry.Register
        (Archive.Temporary_Resources.Preview_File, Owner => 1,
         Path => "/tmp/archive/session/preview", Id => Id1, Stored => Stored);
      Assert (Stored and then Id1 /= Archive.Temporary_Resources.No_Resource, "first resource stored");

      Registry.Register
        (Archive.Temporary_Resources.Extraction_Temporary_File, Owner => 1,
         Path => "/tmp/outside/file", Id => Id2, Stored => Stored);
      Assert (Stored and then Id2 /= Id1, "second resource stored");

      Registry.Register
        (Archive.Temporary_Resources.Diagnostic_Report, Owner => 1,
         Path => "/tmp/archive/session/report", Id => Id3, Stored => Stored);
      Assert (not Stored and then Id3 = Archive.Temporary_Resources.No_Resource, "capacity is bounded");

      Registry.Request_Cleanup (Id1, "/tmp/archive", Decision);
      Assert (Decision = Archive.Temporary_Resources.Cleanup_Allowed, "contained resource may clean");
      Assert
        (Registry.Resource (Id1).State = Archive.Temporary_Resources.Cleanup_Requested,
         "cleanup request updates state");
      Registry.Mark_Cleaned (Id1);
      Assert (Registry.Active_Count = 1, "cleaned resource no longer active");

      Registry.Request_Cleanup (Id2, "/tmp/archive", Decision);
      Assert
        (Decision = Archive.Temporary_Resources.Cleanup_Rejected_Outside_Root,
         "outside resource cleanup rejected");
      Registry.Mark_Failed (Id2);
      Assert (Registry.Active_Count = 0, "failed resource no longer active");
   end Test_Temporary_Resources;

   procedure Test_Selection (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      Model : Archive.Selection.Selection_Model;
      Projection : Archive.Types.Entry_Id_Vectors.Vector;
   begin
      Projection.Append (10);
      Projection.Append (11);
      Projection.Append (12);
      Projection.Append (13);

      Archive.Selection.Select_Only (Model, 10);
      Assert (Archive.Selection.Count (Model) = 1, "select only stores one id");
      Assert (Archive.Selection.Contains (Model, 10), "selected id contained");
      Assert (Archive.Selection.Anchor (Model) = 10, "select only sets anchor");

      Archive.Selection.Add (Model, 12);
      Assert (Archive.Selection.Count (Model) = 2, "additive selection stores two ids");
      Archive.Selection.Toggle (Model, 12);
      Assert (not Archive.Selection.Contains (Model, 12), "toggle removes selected id");
      Archive.Selection.Toggle (Model, 13);
      Assert (Archive.Selection.Contains (Model, 13), "toggle adds absent id");

      Archive.Selection.Select_Range (Model, Projection, Anchor => 11, Target => 13);
      Assert (Archive.Selection.Count (Model) = 3, "range selection includes endpoints");
      Assert
        (Archive.Selection.Contains (Model, 11)
         and then Archive.Selection.Contains (Model, 12)
         and then Archive.Selection.Contains (Model, 13),
         "range selection follows projection order");
   end Test_Selection;

   procedure Test_Navigation (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      Model : Archive.Navigation.Navigation_Model;
      Hist  : Archive.Navigation.History_Entry;
   begin
      Archive.Navigation.Reset (Model, Session => 5, Root => 1);
      Assert (not Archive.Navigation.Can_Back (Model), "fresh root has no back history");
      Assert (Archive.Navigation.Current (Model).Directory = 1, "root is current directory");

      Archive.Navigation.Navigate_To (Model, Directory => 2, Focused => 20, Viewport => 7);
      Archive.Navigation.Navigate_To (Model, Directory => 3, Focused => 30, Viewport => 9);
      Assert (Archive.Navigation.Can_Back (Model), "nested navigation can go back");
      Hist := Archive.Navigation.Back (Model);
      Assert (Hist.Directory = 2 and then Hist.Focused = 20, "back restores previous entry");
      Assert (Archive.Navigation.Can_Forward (Model), "back enables forward");

      Hist := Archive.Navigation.Forward (Model);
      Assert (Hist.Directory = 3 and then Hist.Viewport_First = 9, "forward restores later entry");

      Hist := Archive.Navigation.Back (Model);
      Assert (Hist.Directory = 2, "back before branch returns middle");
      Archive.Navigation.Navigate_To (Model, Directory => 4);
      Assert (not Archive.Navigation.Can_Forward (Model), "new navigation drops forward history");
      Assert (Archive.Navigation.Current (Model).Directory = 4, "branch target is current");

      Archive.Navigation.Reset (Model, Session => 6, Root => 1);
      Assert
        (Archive.Navigation.Current (Model).Session = 6 and then not Archive.Navigation.Can_Back (Model),
         "reset clears history for new session");
   end Test_Navigation;

   procedure Test_Breadcrumb_Snapshot (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      Physical : Archive.Archives.Entries.Entry_Vectors.Vector;
   begin
      Physical.Append (Fixture_Entry ("docs/guides/readme.txt"));
      Physical.Append (Fixture_Entry ("docs/notes.txt"));

      declare
         Build : constant Archive.Archives.Index.Build_Result :=
           Archive.Archives.Index.Build (Physical);
         Index : constant Archive.Archives.Index.Archive_Index := Build.Index;
         Root  : constant Archive.Types.Entry_Id := Archive.Archives.Index.Root_Id (Index);
         Root_Crumbs : constant Archive.View_Snapshots.Breadcrumbs.Breadcrumb_Snapshot :=
           Archive.View_Snapshots.Breadcrumbs.Build (Index, Root);
         Docs_Id : constant Archive.Types.Entry_Id := 2;
         Guides_Id : constant Archive.Types.Entry_Id := 3;
         Guide_Crumbs : constant Archive.View_Snapshots.Breadcrumbs.Breadcrumb_Snapshot :=
           Archive.View_Snapshots.Breadcrumbs.Build (Index, Guides_Id);
         Invalid : constant Archive.View_Snapshots.Breadcrumbs.Breadcrumb_Snapshot :=
           Archive.View_Snapshots.Breadcrumbs.Build (Index, 999);
      begin
         Assert (Build.Status = Archive.Archives.Index.Complete, "breadcrumb fixture index builds");
         Assert (Root_Crumbs.Valid, "root breadcrumb is valid");
         Assert (Natural (Root_Crumbs.Items.Length) = 1, "root breadcrumb has one item");
         Assert
           (Root_Crumbs.Items.Element (1).Entry_Id = Root
            and then To_String (Root_Crumbs.Items.Element (1).Name) = "/",
            "root breadcrumb names archive root");

         Assert (Guide_Crumbs.Valid, "nested breadcrumb is valid");
         Assert (Natural (Guide_Crumbs.Items.Length) = 3, "nested breadcrumb includes ancestors");
         Assert (Guide_Crumbs.Items.Element (1).Entry_Id = Root, "nested breadcrumb starts at root");
         Assert
           (Guide_Crumbs.Items.Element (2).Entry_Id = Docs_Id
            and then To_String (Guide_Crumbs.Items.Element (2).Name) = "docs",
            "nested breadcrumb includes first virtual directory");
         Assert
           (Guide_Crumbs.Items.Element (3).Entry_Id = Guides_Id
            and then To_String (Guide_Crumbs.Items.Element (3).Name) = "guides",
            "nested breadcrumb ends at current directory");

         Assert (not Invalid.Valid, "invalid breadcrumb target is rejected");
         Assert (Natural (Invalid.Items.Length) = 0, "invalid breadcrumb has no items");
      end;
   end Test_Breadcrumb_Snapshot;

   procedure Test_Command_Model (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      Model : Archive.Model.Application_Model;
      Overlay : Archive.Verification.Overlays.Verification_Overlay;
   begin
      Archive.Model.Initialize (Model);
      Assert (Archive.Commands.Command_Count > 20, "commands are registered");
      for Id in Archive.Commands.Registered_Command_Id loop
         declare
            Descriptor : constant Archive.Commands.Command_Descriptor :=
              Archive.Commands.Descriptor (Id, Model);
         begin
            Assert (Descriptor.Id = Id, "command descriptor retains id");
            Assert
              (Archive.Commands.To_String (Descriptor.Identifier) =
               Archive.Commands.Identifier (Id),
               "command descriptor identifier matches registry");
            Assert
              (Archive.Commands.To_String (Descriptor.Name_Key) =
               Archive.Commands.Name_Key (Id),
               "command descriptor name key matches registry");
            Assert
              (Archive.Commands.To_String (Descriptor.Description_Key) =
               Archive.Commands.Description_Key (Id),
               "command descriptor description key matches registry");
            Assert
              (Archive.Commands.To_String (Descriptor.Icon_Name) =
               Archive.Commands.Icon_Name (Id),
               "command descriptor icon matches registry");
            Assert
              (Descriptor.Category = Archive.Commands.Category_For (Id),
               "command descriptor category matches registry");
            Assert
              (Descriptor.Enabled = Archive.Commands.Is_Enabled (Id, Model),
               "command descriptor availability matches registry");
         end;
         Assert (Archive.Commands.Identifier (Id) /= "", "command identifier is present");
         Assert (Archive.Commands.Name_Key (Id) /= "", "command name key is present");
         Assert (Archive.Commands.Description_Key (Id) /= "", "command description key is present");
         Assert (Archive.Commands.Icon_Name (Id) /= "", "command icon token is present");
         Assert
           (Archive.Localization.Text (Archive.Commands.Name_Key (Id)) /=
            Archive.Commands.Name_Key (Id),
            "command name resolves through localization facade");
         Assert
           (Archive.Localization.Text (Archive.Commands.Description_Key (Id)) /=
            Archive.Commands.Description_Key (Id),
            "command description resolves through localization facade");
      end loop;
      Assert (Archive.Commands.Contains ("archive.open"), "open command has stable id");
      Assert (Archive.Commands.Contains ("archive.new"), "new archive command has stable id");
      Assert (Archive.Commands.Contains ("archive.discard_changes"),
              "discard changes command has stable id");
      Assert (Archive.Commands.Contains ("archive.add_files"), "add files command has stable id");
      Assert (Archive.Commands.Contains ("archive.replace_selected"),
              "replace selected command has stable id");
      Assert (Archive.Commands.Contains ("archive.remove_selected"), "remove command has stable id");
      Assert
        (Archive.Commands.Id_For_Identifier ("archive.open") = Archive.Commands.Open_Archive_Command,
         "stable id resolves");
      Assert
        (Archive.Commands.Is_Enabled (Archive.Commands.New_Archive_Command, Model),
         "new archive is enabled without an open archive");
      Assert
        (not Archive.Commands.Is_Enabled (Archive.Commands.Open_Recent_Archive_Command, Model)
         and then Archive.Commands.Unavailable_Key (Archive.Commands.Open_Recent_Archive_Command, Model) =
           "command.unavailable.no_recent_archives",
         "open recent is disabled without recent archives");
      Archive.Commands.Execute (Archive.Commands.New_Archive_Command, Model);
      Assert (Archive.Model.Has_Open_Archive (Model),
              "new archive command creates an archive session");
      Assert (Archive.Model.Has_Index (Model), "new archive command publishes an empty index");
      Assert (Archive.Model.Published_Format (Model) = Archive.Archives.Formats.Zip_Format,
              "new archive defaults to zip format");
      Assert (Archive.Model.Pending_Write_Count (Model) = 1,
              "new archive starts with pending write state");
      Assert (Archive.Model.Lifecycle (Model) = Archive.Model.Archive_Dirty,
              "new archive starts dirty until saved");
      Archive.Model.Close_Archive (Model);
      Assert
        (not Archive.Commands.Is_Enabled (Archive.Commands.Save_Archive_Command, Model)
         and then Archive.Commands.Unavailable_Key (Archive.Commands.Save_Archive_Command, Model) =
           "command.unavailable.no_archive",
         "save reports no-archive reason without an open archive");
      Assert
        (not Archive.Commands.Is_Enabled (Archive.Commands.Close_Archive_Command, Model),
         "close disabled without archive");
      Assert
        (Archive.Commands.Unavailable_Key (Archive.Commands.Close_Archive_Command, Model) =
         "command.unavailable.no_archive",
         "disabled archive command reports stable no-archive reason");
      Assert
        (Archive.Commands.Icon_Name (Archive.Commands.Open_Archive_Command) = "folder-open",
         "open command has stable icon token");
      Assert
        (Archive.Commands.Category_For (Archive.Commands.Verify_Archive_Command) =
         Archive.Commands.Tools_Category,
         "verify command belongs to tools category");

      Archive.Model.Publish_Archive (Model, "sample.zip");
      Assert (Archive.Model.Lifecycle (Model) = Archive.Model.Archive_Ready, "archive state published");
      Assert (Archive.Model.Published_Format (Model) = Archive.Archives.Formats.Zip_Format,
              "source path extension records zip format hint");
      Assert (Archive.Commands.Is_Enabled (Archive.Commands.Open_Recent_Archive_Command, Model),
              "open recent is enabled after publishing a recent archive");
      declare
         Settings : constant Archive.Settings.Settings_Model :=
           Archive.Model.Effective_Settings (Model);
      begin
         Assert
           (Natural (Settings.Recent_Archives.Length) = 1
            and then To_String (Settings.Recent_Archives.Element (1)) = "sample.zip",
            "publishing archive records recent archive");
      end;
      declare
         Hint_Model : Archive.Model.Application_Model;
      begin
         Archive.Model.Initialize (Hint_Model);
         Archive.Model.Publish_Archive (Hint_Model, "bundle.tgz");
         Assert (Archive.Model.Published_Format (Hint_Model) = Archive.Archives.Formats.Tar_GZip_Format,
                 "source path extension records tgz format hint");
         Archive.Model.Publish_Archive (Hint_Model, "unsupported.7z");
         Assert (Archive.Model.Published_Format (Hint_Model) = Archive.Archives.Formats.Seven_Zip_Format,
                 "source path extension records recognized unsupported format hint");
      end;
      Archive.Model.Publish_Archive (Model, "other.zip");
      Archive.Model.Publish_Archive (Model, "sample.zip");
      declare
         Settings : constant Archive.Settings.Settings_Model :=
           Archive.Model.Effective_Settings (Model);
      begin
         Assert (Natural (Settings.Recent_Archives.Length) = 2,
                 "duplicate recent archive is promoted without duplication");
         Assert (To_String (Settings.Recent_Archives.Element (1)) = "sample.zip",
                 "duplicate recent archive promoted to front");
      end;
      Assert
        (Archive.Commands.Is_Enabled (Archive.Commands.Close_Archive_Command, Model),
         "close enabled with archive");
      Assert
        (Archive.Commands.Unavailable_Key (Archive.Commands.Close_Archive_Command, Model) = "",
         "enabled command has no unavailable reason");
      Assert
        (not Archive.Commands.Is_Enabled (Archive.Commands.Extract_Selected_Command, Model)
         and then Archive.Commands.Unavailable_Key (Archive.Commands.Extract_Selected_Command, Model) =
           "command.unavailable.no_selection",
         "selection command reports stable no-selection reason");
      Assert
        (not Archive.Commands.Is_Enabled (Archive.Commands.Save_Archive_Command, Model)
         and then Archive.Commands.Unavailable_Key (Archive.Commands.Save_Archive_Command, Model) =
           "command.unavailable.no_pending_changes",
         "save reports no-pending-changes reason for clean archive session");
      Assert
        (Archive.Commands.Is_Enabled (Archive.Commands.Add_Files_Command, Model),
         "add files is available for an open writable archive session");
      declare
         Read_Only_Model : Archive.Model.Application_Model;
         Physical        : Archive.Archives.Entries.Entry_Vectors.Vector;
      begin
         Archive.Model.Initialize (Read_Only_Model);
         Physical.Append (Fixture_Entry ("visible.txt"));
         declare
            Build : constant Archive.Archives.Index.Build_Result :=
              Archive.Archives.Index.Build (Physical);
         begin
            Archive.Model.Publish_Archive_Index
              (Read_Only_Model, "sample.rar", Build.Index, Archive.Archives.Formats.Rar_Format);
            Assert
              (not Archive.Commands.Is_Enabled (Archive.Commands.Add_Files_Command, Read_Only_Model)
               and then Archive.Commands.Unavailable_Key
                 (Archive.Commands.Add_Files_Command, Read_Only_Model) =
                   "command.unavailable.read_only_archive",
               "add files is disabled for read-only archive formats");
            Assert
              (not Archive.Commands.Is_Enabled (Archive.Commands.Save_Archive_As_Command, Read_Only_Model)
               and then Archive.Commands.Unavailable_Key
                 (Archive.Commands.Save_Archive_As_Command, Read_Only_Model) =
                   "command.unavailable.read_only_archive",
               "save-as is disabled for read-only archive formats");
            Archive.Model.Select_Only (Read_Only_Model, 1);
            Assert
              (not Archive.Commands.Is_Enabled (Archive.Commands.Replace_Selected_Command, Read_Only_Model)
               and then Archive.Commands.Unavailable_Key
                 (Archive.Commands.Replace_Selected_Command, Read_Only_Model) =
                   "command.unavailable.read_only_archive",
               "replace is disabled for read-only archive formats");
            Assert
              (not Archive.Commands.Is_Enabled (Archive.Commands.Remove_Selected_Command, Read_Only_Model)
               and then Archive.Commands.Unavailable_Key
                 (Archive.Commands.Remove_Selected_Command, Read_Only_Model) =
                   "command.unavailable.read_only_archive",
               "remove is disabled for read-only archive formats");
            Assert
              (not Archive.Commands.Is_Enabled (Archive.Commands.Rename_Selected_Command, Read_Only_Model)
               and then Archive.Commands.Unavailable_Key
                 (Archive.Commands.Rename_Selected_Command, Read_Only_Model) =
                   "command.unavailable.read_only_archive",
               "rename is disabled for read-only archive formats");
         end;
      end;
      declare
         Capability_Model : Archive.Model.Application_Model;
         Physical         : Archive.Archives.Entries.Entry_Vectors.Vector;
         Unsafe_Id        : Archive.Types.Entry_Id := Archive.Types.No_Entry;
         Encrypted_Id     : Archive.Types.Entry_Id := Archive.Types.No_Entry;
      begin
         Archive.Model.Initialize (Capability_Model);
         Physical.Append (Fixture_Entry ("safe.txt"));
         Physical.Append (Fixture_Entry ("../outside.txt"));
         declare
            Encrypted : Archive.Archives.Entries.Archive_Entry :=
              Fixture_Entry ("secret.txt");
         begin
            Encrypted.Encryption := Archive.Archives.Entries.Encrypted;
            Physical.Append (Encrypted);
         end;
         declare
            Build : constant Archive.Archives.Index.Build_Result :=
              Archive.Archives.Index.Build (Physical);
            Index : constant Archive.Archives.Index.Archive_Index := Build.Index;
         begin
            Archive.Model.Publish_Archive_Index
              (Capability_Model, "caps.zip", Index, Archive.Archives.Formats.Zip_Format);
            for Raw_Id in 1 .. Archive.Archives.Index.Entry_Count (Index) loop
               declare
                  Id   : constant Archive.Types.Entry_Id := Archive.Types.Entry_Id (Raw_Id);
                  Item : constant Archive.Archives.Entries.Archive_Entry :=
                    Archive.Archives.Index.Entry_For (Index, Id);
               begin
                  if To_String (Item.Original_Path) = "../outside.txt" then
                     Unsafe_Id := Id;
                  elsif To_String (Item.Original_Path) = "secret.txt" then
                     Encrypted_Id := Id;
                  end if;
               end;
            end loop;
         end;

         Archive.Model.Select_Only (Capability_Model, Unsafe_Id);
         Assert
           (not Archive.Commands.Is_Enabled (Archive.Commands.Extract_Selected_Command, Capability_Model)
            and then Archive.Commands.Unavailable_Key
              (Archive.Commands.Extract_Selected_Command, Capability_Model) =
                "unavailable.unsafe_path",
            "extract command reports selected entry path-safety reason");
         Assert
           (not Archive.Commands.Is_Enabled (Archive.Commands.Rename_Selected_Command, Capability_Model)
            and then Archive.Commands.Unavailable_Key
              (Archive.Commands.Rename_Selected_Command, Capability_Model) =
                "unavailable.unsafe_path",
            "rename command reports selected entry path-safety reason");
         Assert
           (not Archive.Commands.Is_Enabled (Archive.Commands.Replace_Selected_Command, Capability_Model)
            and then Archive.Commands.Unavailable_Key
              (Archive.Commands.Replace_Selected_Command, Capability_Model) =
                "unavailable.unsafe_path",
            "replace command reports selected entry path-safety reason");

         Archive.Model.Select_Only (Capability_Model, Encrypted_Id);
         Assert
           (not Archive.Commands.Is_Enabled (Archive.Commands.Preview_Entry_Command, Capability_Model)
            and then Archive.Commands.Unavailable_Key
              (Archive.Commands.Preview_Entry_Command, Capability_Model) =
                "unavailable.encrypted",
            "preview command reports selected entry encryption reason");
      end;
      declare
         Before : constant Archive.Types.Generation_Id :=
           Archive.Model.Session_Generation (Model);
      begin
         Archive.Commands.Execute (Archive.Commands.Reload_Archive_Command, Model);
         Assert (Archive.Model.Session_Generation (Model) = Before,
                 "reload without indexed archive leaves generation unchanged");
      end;
      declare
         Conflict_Model : Archive.Model.Application_Model;
         Physical       : Archive.Archives.Entries.Entry_Vectors.Vector;
         Build          : Archive.Archives.Index.Build_Result;
         Conflict_Config : constant Archive.UI.Shell_Configuration :=
           (Width => 1024,
            Height => 720,
            Locale => To_Unbounded_String ("en"),
            Line_Height => 20);
      begin
         Archive.Model.Initialize (Conflict_Model);
         Physical.Append (Fixture_Entry ("safe/a.txt"));
         Build := Archive.Archives.Index.Build (Physical);
         Archive.Model.Publish_Archive_Index
           (Conflict_Model, "conflicts.zip", Build.Index, Archive.Archives.Formats.Zip_Format);
         Archive.Model.Plan_Add_File (Conflict_Model, "host/a.txt", "safe/a.txt");
         declare
            Plan  : constant Archive.Writes.Plans.Write_Plan :=
              Archive.Model.Current_Write_Plan (Conflict_Model);
            Shell : constant Archive.UI.Shell_Snapshot :=
              Archive.UI.Build_Shell (Conflict_Model, Conflict_Config);
         begin
            Assert
              (Archive.Model.Active_Dialog (Conflict_Model) =
                 Archive.Model.Write_Conflict_Dialog,
               "conflicted write plan opens write conflict prompt");
            Assert
              (Shell.Dialog.Visible
               and then Shell.Dialog.Active = Archive.Model.Write_Conflict_Dialog,
               "ui snapshot exposes write conflict prompt");
            Assert
              (Plan.Status = Archive.Writes.Plans.Write_Plan_Has_Conflicts
               and then Shell.Write.Conflict_Count = 1
               and then Shell.Write.Duplicate_Target_Count = 1,
               "ui write snapshot exposes duplicate conflict summary");
         end;

         Archive.Model.Skip_Write_Conflicts (Conflict_Model);
         declare
            Shell : constant Archive.UI.Shell_Snapshot :=
              Archive.UI.Build_Shell (Conflict_Model, Conflict_Config);
         begin
            Assert
              (Archive.Model.Pending_Write_Count (Conflict_Model) = 0
               and then Archive.Model.Lifecycle (Conflict_Model) = Archive.Model.Archive_Ready
               and then not Shell.Dialog.Visible,
               "apply-to-all skip resolves conflicted write plan and closes prompt");
         end;
      end;
      declare
         Empty_Physical : Archive.Archives.Entries.Entry_Vectors.Vector;
         Build          : constant Archive.Archives.Index.Build_Result :=
           Archive.Archives.Index.Build (Empty_Physical);
         Root           : constant String := "obj/command-save-test";
         Host_File      : constant String := Root & "/readme.txt";
         Target         : constant String := Root & "/sample.zip";
      begin
         if not Ada.Directories.Exists (Root) then
            Ada.Directories.Create_Path (Root);
         end if;
         if Ada.Directories.Exists (Target) then
            Ada.Directories.Delete_File (Target);
         end if;
         Write_Bytes
           (Host_File,
            [1 => Zlib.Byte (Character'Pos ('o')),
             2 => Zlib.Byte (Character'Pos ('k'))]);
         Archive.Model.Publish_Archive_Index
           (Model, Target, Build.Index, Archive.Archives.Formats.Zip_Format);
         Archive.Commands.Execute (Archive.Commands.Add_Files_Command, Model);
         Assert
           (Archive.Model.Active_Dialog (Model) = Archive.Model.Add_Files_Dialog
            and then Archive.Model.Pending_Write_Count (Model) = 0,
            "add files command opens input dialog before planning writes");
         Archive.Model.Plan_Add_File (Model, Host_File, "docs/readme.txt");
      end;
      declare
         Plan : constant Archive.Writes.Plans.Write_Plan := Archive.Model.Current_Write_Plan (Model);
      begin
         Assert (Plan.Status = Archive.Writes.Plans.Write_Plan_Ready,
                 "add file dialog completion publishes ready write plan");
         Assert (Plan.Changes.Element (1).Request.Action = Archive.Writes.Plans.Add_File,
                 "add file write plan records add-file action");
         Assert (Archive.Model.Lifecycle (Model) = Archive.Model.Archive_Dirty,
                 "add file write plan marks archive dirty");
      end;
      Assert (Archive.Commands.Is_Enabled (Archive.Commands.Discard_Changes_Command, Model),
              "dirty archive enables discard changes");
      Archive.Commands.Execute (Archive.Commands.Close_Archive_Command, Model);
      Assert
        (Archive.Model.Active_Dialog (Model) = Archive.Model.Confirm_Close_Dialog
         and then Archive.Model.Lifecycle (Model) = Archive.Model.Archive_Dirty,
         "closing a dirty archive asks for confirmation and preserves the session");
      Archive.Model.Close_Dialog (Model);
      declare
         Before_Save : constant Archive.Types.Generation_Id :=
           Archive.Model.Current_Save_Generation (Model);
      begin
         Archive.Model.Begin_Save (Model);
         declare
            Current_Save : constant Archive.Types.Generation_Id :=
              Archive.Model.Current_Save_Generation (Model);
         begin
            Assert (Current_Save = Before_Save + 1,
                    "begin save allocates a distinct save generation");
            Assert
              (not Archive.Model.Publish_Write_Result
                 (Model, Current_Save + 1, Success => True),
               "model rejects stale save completion generation");
            Assert
              (Archive.Model.Pending_Write_Count (Model) = 1
               and then Archive.Model.Lifecycle (Model) = Archive.Model.Saving_Archive,
               "stale save completion does not mutate pending write state");
            Assert
              (Archive.Model.Publish_Write_Result (Model, Current_Save, Success => False),
               "model accepts current save completion generation");
            Assert
              (Archive.Model.Pending_Write_Count (Model) = 1
               and then Archive.Model.Lifecycle (Model) = Archive.Model.Archive_Save_Failed,
               "failed current save preserves pending writes and records failed state");
         end;
      end;
      Assert (Archive.Commands.Is_Enabled (Archive.Commands.Save_Archive_Command, Model),
              "saveable write plan enables save");
      Archive.Commands.Execute (Archive.Commands.Save_Archive_Command, Model);
      Assert
        (Archive.Model.Pending_Write_Count (Model) = 0
         and then Archive.Model.Lifecycle (Model) = Archive.Model.Archive_Ready
         and then not Archive.Commands.Is_Enabled (Archive.Commands.Save_Archive_Command, Model),
         "save command clears pending writes");
      Archive.Model.Plan_Add_Directory (Model, "host/newdocs", "newdocs");
      Assert (Archive.Model.Current_Write_Plan (Model).Changes.Element (1).Request.Action =
                Archive.Writes.Plans.Add_Directory,
              "add directory dialog completion publishes write plan");
      Archive.Commands.Execute (Archive.Commands.Discard_Changes_Command, Model);
      Assert
        (Archive.Model.Pending_Write_Count (Model) = 0
         and then Archive.Model.Lifecycle (Model) = Archive.Model.Archive_Ready
         and then not Archive.Commands.Is_Enabled (Archive.Commands.Discard_Changes_Command, Model),
         "discard changes clears the staged write plan");
      Archive.Model.Plan_Add_Directory (Model, "host/newdocs", "newdocs");
      Assert
        (not Archive.Model.Publish_Write_Result
           (Model, Archive.Types.No_Generation, Success => False),
         "model rejects save completion without an active save operation");
      declare
         Dirty_Generation : constant Archive.Types.Generation_Id :=
           Archive.Model.Session_Generation (Model);
      begin
         Archive.Model.Begin_Save (Model);
         Assert
           (Archive.Model.Publish_Write_Result
              (Model, Archive.Model.Current_Save_Generation (Model), Success => False),
            "model accepts failed active save completion");
         Assert
           (Archive.Model.Pending_Write_Count (Model) = 1
            and then Archive.Model.Lifecycle (Model) = Archive.Model.Archive_Save_Failed
            and then Archive.Model.Session_Generation (Model) = Dirty_Generation,
            "failed write publication preserves pending writes and current archive generation");
      end;
      declare
         Failed_Generation : constant Archive.Types.Generation_Id :=
           Archive.Model.Session_Generation (Model);
      begin
         Archive.Model.Begin_Save (Model);
         Assert
           (Archive.Model.Publish_Write_Result
              (Model, Archive.Model.Current_Save_Generation (Model), Success => True),
            "model accepts successful active save completion");
         Assert
           (Archive.Model.Pending_Write_Count (Model) = 0
            and then Archive.Model.Lifecycle (Model) = Archive.Model.Archive_Ready
            and then Archive.Model.Session_Generation (Model) = Failed_Generation + 1,
            "successful write publication clears pending writes and publishes a new generation");
      end;
      Assert
        (not Archive.Commands.Is_Enabled (Archive.Commands.Remove_Selected_Command, Model)
         and then Archive.Commands.Unavailable_Key (Archive.Commands.Remove_Selected_Command, Model) =
           "command.unavailable.no_selection",
         "remove reports no-selection reason with no selected entries");
      Archive.Model.Set_Selected_Count (Model, 1);
      Assert
        (Archive.Commands.Is_Enabled (Archive.Commands.Remove_Selected_Command, Model)
         and then Archive.Commands.Is_Enabled (Archive.Commands.Rename_Selected_Command, Model),
         "selected-entry mutation commands become available with selection");
      Archive.Commands.Execute (Archive.Commands.Rename_Selected_Command, Model);
      Assert (Archive.Model.Active_Dialog (Model) = Archive.Model.Rename_Entry_Dialog,
              "rename command opens rename dialog before planning writes");
      declare
         Indexed_Model : Archive.Model.Application_Model;
         Physical      : Archive.Archives.Entries.Entry_Vectors.Vector;
      begin
         Archive.Model.Initialize (Indexed_Model);
         Physical.Append (Fixture_Entry ("remove-me.txt"));
         declare
            Build : constant Archive.Archives.Index.Build_Result :=
              Archive.Archives.Index.Build (Physical);
            File_Id : Archive.Types.Entry_Id := Archive.Types.No_Entry;
         begin
            for Raw_Id in 1 .. Archive.Archives.Index.Entry_Count (Build.Index) loop
               declare
                  Id   : constant Archive.Types.Entry_Id := Archive.Types.Entry_Id (Raw_Id);
                  Item : constant Archive.Archives.Entries.Archive_Entry :=
                    Archive.Archives.Index.Entry_For (Build.Index, Id);
               begin
                  if To_String (Item.Original_Path) = "remove-me.txt" then
                     File_Id := Id;
                  end if;
               end;
            end loop;
            Archive.Model.Publish_Archive_Index
              (Indexed_Model, "writable.zip", Build.Index, Archive.Archives.Formats.Zip_Format);
            Archive.Model.Select_Only (Indexed_Model, File_Id);
            Assert
              (Archive.Commands.Is_Enabled (Archive.Commands.Replace_Selected_Command, Indexed_Model),
               "replace selected is enabled for a writable regular file");
            Archive.Commands.Execute (Archive.Commands.Replace_Selected_Command, Indexed_Model);
            Assert (Archive.Model.Active_Dialog (Indexed_Model) = Archive.Model.Replace_File_Dialog,
                    "replace command opens replacement source dialog before planning writes");
            Archive.Model.Plan_Selected_Replacement (Indexed_Model, "host/replacement.txt");
            declare
               Plan : constant Archive.Writes.Plans.Write_Plan :=
                 Archive.Model.Current_Write_Plan (Indexed_Model);
            begin
               Assert (Plan.Status = Archive.Writes.Plans.Write_Plan_Ready,
                       "replace dialog completion publishes ready write plan");
               Assert
                 (Plan.Changes.Element (1).Request.Action = Archive.Writes.Plans.Replace_File
                  and then Plan.Changes.Element (1).Request.Source_Entry = File_Id
                  and then To_String (Plan.Changes.Element (1).Request.Target_Path) = "remove-me.txt",
                  "replace write plan keeps selected id and original archive path");
            end;
            Archive.Model.Clear_Pending_Writes (Indexed_Model);
            Archive.Model.Select_Only (Indexed_Model, File_Id);
            Archive.Commands.Execute (Archive.Commands.Remove_Selected_Command, Indexed_Model);
            declare
               Plan : constant Archive.Writes.Plans.Write_Plan :=
                 Archive.Model.Current_Write_Plan (Indexed_Model);
            begin
               Assert (Plan.Status = Archive.Writes.Plans.Write_Plan_Ready,
                       "remove command publishes a ready write plan");
               Assert (Plan.Session = Archive.Model.Session_Generation (Indexed_Model),
                       "write plan is tied to the current session generation");
               Assert
                 (Natural (Plan.Changes.Length) = 1
                  and then Plan.Changes.Element (1).Request.Action =
                    Archive.Writes.Plans.Remove_Entry,
                  "write plan records selected removal by stable entry id");
               Assert (Archive.Model.Pending_Write_Count (Indexed_Model) = 1,
                       "remove command records planned write count");
            end;
            Archive.Model.Publish_Write_Result (Indexed_Model, Success => True);
            Archive.Model.Select_Only (Indexed_Model, File_Id);
            Archive.Model.Plan_Selected_Rename (Indexed_Model, "renamed.txt");
            declare
               Plan : constant Archive.Writes.Plans.Write_Plan :=
                 Archive.Model.Current_Write_Plan (Indexed_Model);
            begin
               Assert (Plan.Status = Archive.Writes.Plans.Write_Plan_Ready,
                       "rename dialog completion publishes ready write plan");
               Assert (Plan.Changes.Element (1).Request.Action = Archive.Writes.Plans.Rename_Entry,
                       "rename write plan records rename action");
               Assert (Plan.Changes.Element (1).Request.Source_Entry = File_Id,
                       "rename write plan uses selected entry id");
               Assert (Archive.Model.Has_Saveable_Write_Plan (Indexed_Model),
                       "ready rename write plan is saveable");
            end;
         end;
      end;
      Archive.Model.Set_Selected_Count (Model, 0);
      Archive.Commands.Execute (Archive.Commands.Select_Details_View_Command, Model);
      Assert (Archive.Model.View_Mode (Model) = Archive.Types.Details_View, "view command mutates model");

      Archive.Commands.Execute (Archive.Commands.Open_Recent_Archive_Command, Model);
      Assert
        (Archive.Model.Last_Lifecycle_Request (Model) = Archive.Model.Open_Recent_Request
         and then Archive.Model.Active_Dialog (Model) = Archive.Model.Open_Archive_Dialog,
         "open recent records lifecycle request and opens archive dialog");
      Archive.Model.Close_Dialog (Model);

      Assert
        (Archive.Model.Current_Verification_Generation (Model) = Archive.Types.No_Generation,
         "verification generation starts empty");
      Archive.Commands.Execute (Archive.Commands.Verify_Archive_Command, Model);
      Assert
        (Archive.Model.Current_Verification_Generation (Model) = 1,
         "verify command starts verification generation");

      Overlay :=
        Archive.Verification.Overlays.Empty
          (Archive.Model.Session_Generation (Model),
           Archive.Model.Current_Verification_Generation (Model),
           Archive.Verification.Overlays.Verification_Completed);
      Archive.Verification.Overlays.Set_Result
        (Overlay, 2, Archive.Archives.Entries.Verified, "verification.ok");
      Assert
        (Archive.Model.Publish_Verification (Model, Overlay) =
         Archive.Verification.Overlays.Overlay_Accepted,
         "model accepts current verification overlay");
      Assert
        (Archive.Model.Verification_Entry_Count (Model) = 1
         and then Archive.Model.Verification_Integrity (Model, 2) =
           Archive.Archives.Entries.Verified,
         "model stores accepted verification overlay");

      Archive.Model.Start_Verification (Model);
      Assert
        (Archive.Model.Publish_Verification (Model, Overlay) =
         Archive.Verification.Overlays.Overlay_Rejected_Stale,
         "model rejects stale verification overlay");
      Assert
        (Archive.Model.Verification_Entry_Count (Model) = 0,
         "starting new verification clears old overlay results");
   end Test_Command_Model;

   procedure Test_Command_Palette_Snapshot (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      Model : Archive.Model.Application_Model;
      Request : Archive.View_Snapshots.Command_Palette.Palette_Request :=
        (Locale      => To_Unbounded_String ("en"),
         Filter_Text => To_Unbounded_String (""),
         Limit       => 200);
   begin
      Archive.Model.Initialize (Model);

      declare
         Snapshot : constant Archive.View_Snapshots.Command_Palette.Palette_Snapshot :=
           Archive.View_Snapshots.Command_Palette.Build (Model, Request);
         First : constant Archive.View_Snapshots.Command_Palette.Command_Row :=
           Snapshot.Rows.Element (1);
      begin
         Assert
           (Natural (Snapshot.Rows.Length) = Archive.Commands.Command_Count,
            "palette snapshot includes every registered command");
         Assert (not Snapshot.Truncated, "unlimited palette snapshot is not truncated");
         Assert (To_String (First.Name) /= Archive.Commands.Name_Key (First.Id),
                 "palette row name is localized");
         Assert (To_String (First.Description) /= Archive.Commands.Description_Key (First.Id),
                 "palette row description is localized");
         Assert (To_String (First.Icon_Name) /= "", "palette row includes icon token");
      end;

      Request.Filter_Text := To_Unbounded_String ("verify");
      declare
         Snapshot : constant Archive.View_Snapshots.Command_Palette.Palette_Snapshot :=
           Archive.View_Snapshots.Command_Palette.Build (Model, Request);
         Row : constant Archive.View_Snapshots.Command_Palette.Command_Row :=
           Snapshot.Rows.Element (1);
      begin
         Assert (Natural (Snapshot.Rows.Length) = 1, "palette filter matches command text");
         Assert (Row.Id = Archive.Commands.Verify_Archive_Command, "filtered palette returns verify command");
         Assert (not Row.Enabled, "verify command disabled without archive");
         Assert
           (To_String (Row.Unavailable_Text) =
            Archive.Localization.Text ("command.unavailable.no_archive"),
            "disabled palette row resolves unavailable text");
      end;

      Archive.Model.Publish_Archive (Model, "sample.zip");
      declare
         Snapshot : constant Archive.View_Snapshots.Command_Palette.Palette_Snapshot :=
           Archive.View_Snapshots.Command_Palette.Build (Model, Request);
         Row : constant Archive.View_Snapshots.Command_Palette.Command_Row :=
           Snapshot.Rows.Element (1);
      begin
         Assert (Row.Enabled, "verify command enabled with archive");
         Assert (To_String (Row.Unavailable_Text) = "", "enabled palette row has no unavailable text");
         Assert (Row.Shortcut_Present, "verify palette row exposes shortcut presence");
      end;

      Request.Filter_Text := To_Unbounded_String ("");
      Request.Limit := 1;
      declare
         Snapshot : constant Archive.View_Snapshots.Command_Palette.Palette_Snapshot :=
           Archive.View_Snapshots.Command_Palette.Build (Model, Request);
      begin
         Assert (Natural (Snapshot.Rows.Length) = 1, "palette limit caps rows");
         Assert (Snapshot.Truncated, "palette truncation is reported");
      end;
   end Test_Command_Palette_Snapshot;

   procedure Test_Command_Surface_Snapshots (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      Model : Archive.Model.Application_Model;
      Locale : constant Archive.Types.UString := To_Unbounded_String ("en");
   begin
      Archive.Model.Initialize (Model);

      declare
         Menus : constant Archive.View_Snapshots.Command_Surfaces.Menu_Snapshot :=
           Archive.View_Snapshots.Command_Surfaces.Build_Menus (Model, Locale);
         Total : Natural := 0;
      begin
         Assert (Natural (Menus.Sections.Length) = 7, "menu snapshot includes command categories");
         for Section of Menus.Sections loop
            Assert (To_String (Section.Name) /= "", "menu section name is localized");
            Total := Total + Natural (Section.Commands.Length);
            for Row of Section.Commands loop
               Assert (To_String (Row.Name) /= "", "menu command name is localized");
               Assert (To_String (Row.Description) /= "", "menu command description is localized");
               Assert (To_String (Row.Icon_Name) /= "", "menu command has icon token");
            end loop;
         end loop;
         Assert (Total = Archive.Commands.Command_Count, "menus contain every registered command once");
      end;

      declare
         Toolbar : constant Archive.View_Snapshots.Command_Surfaces.Toolbar_Snapshot :=
           Archive.View_Snapshots.Command_Surfaces.Build_Toolbar (Model, Locale);
         Verify_Row : constant Archive.View_Snapshots.Command_Surfaces.Surface_Command :=
           Toolbar.Commands.Element (7);
      begin
         Assert (Natural (Toolbar.Commands.Length) = 8, "toolbar snapshot has stable command set");
         Assert (Toolbar.Commands.Element (1).Id = Archive.Commands.Open_Archive_Command,
                 "toolbar starts with open archive");
         Assert (Toolbar.Commands.Element (2).Id = Archive.Commands.New_Archive_Command,
                 "toolbar includes new archive");
         Assert (Toolbar.Commands.Element (4).Id = Archive.Commands.Add_Files_Command,
                 "toolbar includes add files");
         Assert (Toolbar.Commands.Element (5).Id = Archive.Commands.Save_Archive_Command,
                 "toolbar includes save archive");
         Assert (Verify_Row.Id = Archive.Commands.Verify_Archive_Command,
                 "toolbar includes verify command");
         Assert (not Verify_Row.Enabled, "verify toolbar command disabled without archive");
         Assert
           (To_String (Verify_Row.Unavailable_Text) =
            Archive.Localization.Text ("command.unavailable.no_archive"),
            "toolbar resolves unavailable text");
      end;

      Archive.Model.Publish_Archive (Model, "sample.zip");
      declare
         Toolbar : constant Archive.View_Snapshots.Command_Surfaces.Toolbar_Snapshot :=
           Archive.View_Snapshots.Command_Surfaces.Build_Toolbar (Model, Locale);
      begin
         Assert (Toolbar.Commands.Element (7).Enabled, "verify toolbar command enabled with archive");
         Assert (To_String (Toolbar.Commands.Element (7).Unavailable_Text) = "",
                 "enabled toolbar command has no unavailable text");
         Assert (Toolbar.Commands.Element (4).Enabled, "add-files toolbar command enabled with archive");
         Assert (not Toolbar.Commands.Element (5).Enabled, "save toolbar command waits for pending write");
      end;
   end Test_Command_Surface_Snapshots;

   procedure Test_UI_Shell (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      Model : Archive.Model.Application_Model;
      Physical : Archive.Archives.Entries.Entry_Vectors.Vector;
      Config : constant Archive.UI.Shell_Configuration :=
        (Width => 1024,
         Height => 720,
         Locale => To_Unbounded_String ("en"),
         Line_Height => 20);
   begin
      Archive.Model.Initialize (Model);
      declare
         Shell : constant Archive.UI.Shell_Snapshot :=
           Archive.UI.Build_Shell (Model, Config);
      begin
         Assert (To_String (Shell.Title) = "archive", "ui shell title is localized");
         Assert (To_String (Shell.Status_Text) = "No archive open.", "ui shell status is localized");
         Assert (Natural (Shell.Menus.Sections.Length) = 7, "ui shell contains menus");
         Assert (Natural (Shell.Toolbar.Commands.Length) = 8, "ui shell contains toolbar commands");
         Assert (not Shell.Breadcrumb.Valid, "no-archive shell has no breadcrumb");
         Assert (Natural (Shell.Breadcrumb.Items.Length) = 0,
                 "no-archive breadcrumb is empty");
         Assert (Natural (Shell.Content_Projection.Entries.Length) = 0,
                 "no-archive content projection is empty");
         Assert (not Shell.Content_Projection.Truncated,
                 "no-archive content projection is not truncated");
         Assert (Natural (Shell.Command_Palette.Rows.Length) = Archive.Commands.Command_Count,
                 "ui shell includes command palette rows");
         Assert (not Shell.Command_Palette.Truncated,
                 "ui shell command palette is not truncated");
         Assert (Shell.Layout.Toolbar_H > 0, "ui shell computes toolbar height");
         Assert (Shell.Layout.Content_H > 0, "ui shell computes content region");
         Assert (Shell.Layout.Content_W + Shell.Layout.Preview_W = Config.Width,
                 "content and preview regions fill width");
         Assert (Shell.Layout.Preview_W > 0, "wide ui shell shows preview region");
         Assert (Shell.Layout.Status_Y + Shell.Layout.Status_H = Config.Height,
                 "status region is anchored at bottom");
         Assert (To_String (Shell.Status_Bar.Text) = "No archive open.",
                 "status bar text is localized");
         Assert (To_String (Shell.Status_Bar.Accessible_Name) = "Status bar",
                 "status bar accessible name is localized");
         Assert (Shell.Status_Bar.Lifecycle = Archive.Model.No_Archive,
                 "status bar tracks lifecycle");
         Assert (Shell.Status_Bar.Selected_Count = 0,
                 "status bar tracks selected count");
         Assert (not Shell.Status_Bar.Has_Pending_Writes,
                 "status bar tracks pending write state");
         Assert (Shell.Status_Bar.Pending_Write_Count = 0,
                 "status bar tracks pending write count");
         Assert (Shell.Status_Bar.Verification_Count = 0,
                 "status bar tracks verification count");
         Assert (Shell.Selection.Count = 0, "ui shell selection starts empty");
         Assert (Natural (Shell.Selection.Items.Length) = 0,
                 "ui shell selection has no initial entries");
         Assert (Shell.Selection.Anchor = Archive.Types.No_Entry,
                 "ui shell selection has no initial anchor");
         Assert (Shell.Preview_Panel.Visible, "preview panel is visible by default");
         Assert (Shell.Preview_Panel.Phase = Archive.Model.No_Preview,
                 "preview panel starts idle");
         Assert (Shell.Preview_Panel.Entry_Id = Archive.Types.No_Entry,
                 "preview panel starts without target entry");
         Assert (To_String (Shell.Preview_Panel.Accessible_Name) = "Preview panel",
                 "preview panel accessible name is localized");
         Assert (To_String (Shell.Preview_Panel.State_Text) = "No preview",
                 "preview panel state text is localized");
         Assert (Shell.Navigation.Current_Directory = Archive.Types.No_Entry,
                 "ui shell navigation starts without directory");
         Assert (not Shell.Navigation.Can_Back, "ui shell navigation starts without back");
         Assert (not Shell.Navigation.Can_Forward, "ui shell navigation starts without forward");
         Assert (Shell.Copy_Result.Kind = Archive.Model.No_Copy_Result,
                 "ui shell copy result starts empty");
         Assert (To_String (Shell.Copy_Result.Text) = "",
                 "ui shell copy result text starts empty");
         Assert (Shell.Settings.Default_View = Archive.Types.Grid_View,
                 "ui shell settings expose default view");
         Assert (Shell.Settings.Directories_First,
                 "ui shell settings expose directories-first default");
         Assert (Shell.Settings.Preview_Visible,
                 "ui shell settings expose preview visibility");
         Assert (Shell.Settings.Recent_Count = 0,
                 "ui shell settings expose empty recent archive count");
         Assert (To_String (Shell.Settings.Title) = "Settings",
                 "ui shell settings title is localized");
         Assert (To_String (Shell.Settings.View_Label) = "Default view",
                 "ui shell settings field labels are localized");
         Assert
           (Shell.Settings.Preview_Byte_Limit =
            Archive.Settings.Default_Settings.Preview_Byte_Limit,
            "ui shell settings expose preview byte limit");
         Assert
           (Shell.Settings.Per_Entry_Extraction_Limit =
            Archive.Settings.Default_Settings.Per_Entry_Extraction_Limit
            and then Shell.Settings.Total_Extraction_Limit =
              Archive.Settings.Default_Settings.Total_Extraction_Limit,
            "ui shell settings expose extraction output limits");
         Assert
           (To_String (Shell.Settings.Per_Entry_Extraction_Limit_Label) =
              "Per-entry extraction limit"
            and then To_String (Shell.Settings.Total_Extraction_Limit_Label) =
              "Total extraction limit",
            "ui shell extraction limit labels are localized");
         Assert (Shell.Verification.Phase = Archive.Verification.Overlays.Verification_Not_Run,
                 "ui shell verification starts not run");
         Assert (Shell.Verification.Entry_Count = 0,
                 "ui shell verification starts without entry results");
         Assert (Shell.Extraction.Phase = Archive.Model.No_Extraction,
                 "ui shell extraction starts idle");
         Assert (Shell.Extraction.Entry_Count = 0,
                 "ui shell extraction starts without plan entries");
         Assert
           (Shell.Extraction.Last_Status = Archive.Extraction.Results.Completed
            and then Shell.Extraction.Last_Plan_Status =
              Archive.Extraction.Results.Execution_Completed,
            "ui shell extraction starts with neutral terminal status");
         Assert
           (Shell.Extraction.Completed_Count = 0
            and then Shell.Extraction.Failed_Count = 0
            and then Shell.Extraction.Last_Blocked_Count = 0,
            "ui shell extraction starts without terminal counts");
         Assert (Shell.Write.Change_Count = 0,
                 "ui shell write snapshot starts without planned changes");
         Assert (not Shell.Write.Has_Pending,
                 "ui shell write snapshot starts clean");
         Assert (Shell.Write.Last_Status = Archive.Writes.Results.Write_Completed,
                 "ui shell write snapshot starts with neutral terminal status");
         Assert (Shell.Source.Status = Archive.Source_Monitoring.Source_Missing,
                 "ui shell source starts missing");
         Assert (Shell.Source.Change = Archive.Model.No_Source_Change,
                 "ui shell source starts without source-change alert");
         Assert (To_String (Shell.Source.Path) = "",
                 "ui shell source path starts empty");
         Assert (Shell.Lifecycle_Request.Request = Archive.Model.No_Lifecycle_Request,
                 "ui shell lifecycle request starts empty");
         Assert (Shell.Content_View.Mode = Archive.Types.Grid_View, "default ui content mode is grid");
         Assert (To_String (Shell.Content_View.Label) = "Grid view", "grid view label is localized");
         Assert
           (To_String (Shell.Content_View.Accessible_Name) = "Archive contents grid",
            "grid accessible name is localized");
         Assert (Shell.Content_View.Virtualized, "content view is virtualized");
         Assert (Shell.Content_View.Keyboard_Navigation, "content view supports keyboard navigation");
         Assert (Shell.Content_View.Type_Ahead, "content view supports type-ahead metadata");
         Assert (To_String (Shell.Content_View.Selection_Model) = "entry-id",
                 "content view uses entry-id selection");
         Assert (To_String (Shell.Content_View.Filter_Text) = "",
                 "content view exposes filter text");
         Assert (Shell.Content_View.Sort_Field = Archive.View_Snapshots.Sort_By_Name,
                 "content view exposes sort field");
         Assert (Shell.Content_View.Sort_Direction = Archive.View_Snapshots.Ascending,
                 "content view exposes sort direction");
         Assert (Shell.Content_View.Directories_First,
                 "content view exposes directories-first state");
         Assert
           (Natural (Shell.Content_View.Details_Columns.Length) = 7,
            "content view exposes default details columns");
         Assert
           (Shell.Content_View.Details_Columns.Element (1) =
              Archive.View_Snapshots.Columns.Name_Column,
            "content view columns use stable column ids");
         Assert (Shell.Focus.Region = Archive.Model.Content_Focus, "content owns initial focus");
         Assert (To_String (Shell.Focus.Accessible_Name) = "Archive contents focus",
                 "initial focus name is localized");
         Assert (not Shell.Overlay.Visible, "no overlay visible initially");
         Assert (Shell.Overlay.Priority = 0, "no overlay has no priority");
         Assert (not Shell.Dialog.Visible, "no dialog visible initially");
         Assert (not Shell.Notification.Visible, "no notification visible initially");
         Assert
           (To_String (Shell.Focus_Command_Id) =
              Archive.Commands.Identifier (Archive.Commands.Open_Archive_Command),
            "initial focus command is open archive");
      end;

      declare
         Settings_Model : Archive.Model.Application_Model;
         Settings       : Archive.Settings.Settings_Model :=
           Archive.Settings.Default_Settings;
      begin
         Archive.Model.Initialize (Settings_Model);
         Settings.Default_View := Archive.Types.Compact_View;
         Settings.Directories_First := False;
         Settings.Preview_Visible := False;
         Settings.Preview_Byte_Limit := 64;
         Settings.Conflict_Policy := Archive.Settings.Rename;
         Settings.Write_Conflict_Policy := Archive.Settings.Overwrite;
         Settings.Link_Policy := Archive.Settings.Safe_Internal_Links;
         Settings.Show_Unsafe_Entries := False;
         Settings.Startup_Reopen_Recent := True;
         Settings.Window_Maximized := True;
         Archive.Settings.Remember_Recent_Archive (Settings, "alpha.zip");
         Archive.Settings.Remember_Recent_Archive (Settings, "beta.zip");
         Settings.Details_Columns.Clear;
         Settings.Details_Columns.Append (Archive.View_Snapshots.Columns.Name_Column);
         Settings.Details_Columns.Append (Archive.View_Snapshots.Columns.Path_Safety_Column);
         Archive.Model.Apply_Settings (Settings_Model, Settings);
         declare
            Shell : constant Archive.UI.Shell_Snapshot :=
              Archive.UI.Build_Shell (Settings_Model, Config);
         begin
            Assert (Shell.View_Mode = Archive.Types.Compact_View,
                    "applied settings update model view mode");
            Assert (Shell.Content_View.Mode = Archive.Types.Compact_View,
                    "ui shell content view follows applied settings");
            Assert (not Shell.Content_View.Directories_First,
                    "ui shell content view follows settings directories-first");
            Assert (not Shell.Preview_Visible,
                    "ui shell preview visibility follows applied settings");
            Assert (Shell.Layout.Preview_W = 0,
                    "hidden preview from settings has zero width");
            Assert (Shell.Settings.Preview_Byte_Limit = 64,
                    "ui shell settings snapshot carries applied preview limit");
            Assert (Shell.Settings.Conflict_Policy = Archive.Settings.Rename,
                    "ui shell settings snapshot carries conflict policy");
            Assert (Shell.Settings.Write_Conflict_Policy = Archive.Settings.Overwrite,
                    "ui shell settings snapshot carries write conflict policy");
            Assert (Shell.Settings.Link_Policy = Archive.Settings.Safe_Internal_Links,
                    "ui shell settings snapshot carries link policy");
            Assert (not Shell.Settings.Show_Unsafe_Entries,
                    "ui shell settings snapshot carries unsafe-entry visibility");
            Assert
              (Shell.Settings.Startup_Reopen_Recent
               and then Shell.Settings.Window_Maximized,
               "ui shell settings snapshot carries startup and window policies");
            Assert (To_String (Shell.Settings.Conflict_Policy_Label) = "Extraction conflicts",
                    "ui shell settings conflict policy label is localized");
            Assert (To_String (Shell.Settings.Write_Conflict_Policy_Label) = "Write conflicts",
                    "ui shell settings write conflict policy label is localized");
            Assert (To_String (Shell.Settings.Conflict_Rename_Label) = "Rename",
                    "ui shell settings conflict option labels are localized");
            Assert (To_String (Shell.Settings.Link_Safe_Internal_Label) = "Safe internal links",
                    "ui shell settings link option labels are localized");
            Assert (To_String (Shell.Settings.Show_Unsafe_Entries_Label) = "Show unsafe entries",
                    "ui shell settings unsafe-entry label is localized");
            Assert
              (To_String (Shell.Settings.Startup_Reopen_Recent_Label) =
                 "Reopen most recent archive at startup"
               and then To_String (Shell.Settings.Window_Maximized_Label) = "Maximize window",
               "ui shell settings startup and window labels are localized");
            Assert (Shell.Settings.Recent_Count = 2,
                    "ui shell settings snapshot carries recent archive count");
            Assert (To_String (Shell.Settings.Recent_Archives.Element (1)) = "beta.zip",
                    "ui shell settings snapshot carries recent archive paths");
            Assert
              (Natural (Shell.Content_View.Details_Columns.Length) = 2,
               "ui shell content view follows applied details columns");
            Assert
              (Shell.Content_View.Details_Columns.Element (2) =
                 Archive.View_Snapshots.Columns.Path_Safety_Column,
               "ui shell content view preserves details column ids");
         end;
      end;

      Archive.Model.Set_Preview_Visible (Model, False);
      declare
         Shell : constant Archive.UI.Shell_Snapshot :=
           Archive.UI.Build_Shell (Model, Config);
      begin
         Assert (not Shell.Preview_Visible, "ui shell tracks preview visibility");
         Assert (Shell.Layout.Preview_W = 0, "hidden preview has zero width");
      end;

      declare
         Result : constant Archive.UI.Dispatch_Result :=
           Archive.UI.Dispatch_Command
             (Model, Archive.Commands.Toggle_Preview_Command, Archive.UI.Toolbar_Source);
      begin
         Assert (Result.Matched and then not Result.Accepted, "disabled toolbar dispatch is rejected");
         declare
            Shell : constant Archive.UI.Shell_Snapshot :=
              Archive.UI.Build_Shell (Model, Config);
         begin
            Assert (Shell.Notification.Visible, "disabled command creates notification");
            Assert (Shell.Notification.Severity = Archive.Model.Warning_Notification,
                    "disabled command notification is warning");
            Assert
              (To_String (Shell.Notification.Text) = "Command unavailable.",
               "disabled command notification is localized");
         end;
      end;

      Archive.Model.Clear_Notification (Model);
      declare
         Result : constant Archive.UI.Dispatch_Result :=
           Archive.UI.Dispatch_Shortcut
             (Model, Guikit.Input.Key_Down, Guikit.Input.No_Modifiers);
      begin
         Assert (Result.Matched and then Result.Accepted, "content arrow navigation is handled");
      end;

      declare
         Result : constant Archive.UI.Dispatch_Result :=
           Archive.UI.Dispatch_Shortcut
             (Model, Guikit.Input.Key_Tab, Guikit.Input.No_Modifiers);
      begin
         Assert (Result.Matched and then Result.Accepted, "Tab advances focus");
         Assert (Archive.Model.Current_Focus (Model) = Archive.Model.Toolbar_Focus,
                 "Tab moves content focus to toolbar");
      end;

      declare
         Mods : Guikit.Input.Modifier_Set := Guikit.Input.No_Modifiers;
      begin
         Mods (Guikit.Input.Shift_Key) := True;
         declare
            Result : constant Archive.UI.Dispatch_Result :=
              Archive.UI.Dispatch_Shortcut (Model, Guikit.Input.Key_Tab, Mods);
         begin
            Assert (Result.Matched and then Result.Accepted, "Shift+Tab reverses focus");
            Assert (Archive.Model.Current_Focus (Model) = Archive.Model.Content_Focus,
                    "Shift+Tab restores content focus");
         end;
      end;

      declare
         Result : constant Archive.UI.Dispatch_Result :=
           Archive.UI.Dispatch_Command
             (Model, Archive.Commands.Open_Archive_Command, Archive.UI.Toolbar_Source);
      begin
         Assert (Result.Matched and then Result.Accepted, "open archive dispatch accepted");
         declare
            Shell : constant Archive.UI.Shell_Snapshot :=
              Archive.UI.Build_Shell (Model, Config);
         begin
            Assert (Shell.Dialog.Visible, "open archive dispatch opens dialog");
            Assert (Shell.Dialog.Active = Archive.Model.Open_Archive_Dialog,
                    "open archive dialog active");
            Assert (Shell.Dialog.Modal, "open archive dialog is modal");
            Assert
              (To_String (Shell.Dialog.Title) = "Open archive",
               "open archive dialog title is localized");
         end;
      end;

      declare
         Result : constant Archive.UI.Dispatch_Result :=
           Archive.UI.Dispatch_Shortcut
             (Model, Guikit.Input.Key_Escape, Guikit.Input.No_Modifiers);
      begin
         Assert (Result.Matched and then Result.Accepted, "Escape closes dialog");
         Assert (not Archive.UI.Build_Shell (Model, Config).Dialog.Visible,
                 "dialog closed after Escape");
      end;

      Archive.Model.Create_New_Archive (Model);
      Archive.Model.Set_Selected_Count (Model, 2);
      Archive.Model.Plan_Add_File (Model, "host/readme.txt", "docs/readme.txt");
      declare
         Shell : constant Archive.UI.Shell_Snapshot :=
           Archive.UI.Build_Shell (Model, Config);
      begin
         Assert (Shell.Status_Bar.Lifecycle = Archive.Model.Archive_Dirty,
                 "status bar tracks dirty lifecycle");
         Assert (To_String (Shell.Status_Bar.Text) = "Archive has unsaved changes.",
                 "dirty status text is localized");
         Assert (Shell.Status_Bar.Selected_Count = 2,
                 "status bar reports selected entries");
         Assert (Shell.Selection.Count = 2,
                 "ui shell selection reports selected entry count");
         Assert (Natural (Shell.Selection.Items.Length) = 2,
                 "ui shell selection carries selected entry ids");
         Assert (Shell.Selection.Anchor = 1,
                 "ui shell selection carries selection anchor");
         Assert (Shell.Status_Bar.Pending_Write_Count = 1,
                 "status bar reports pending writes");
         Assert (Shell.Status_Bar.Has_Pending_Writes,
                 "status bar exposes pending-write availability");
         Assert (Shell.Write.Has_Pending,
                 "ui shell write snapshot exposes pending writes");
         Assert (Shell.Write.Saveable,
                 "ui shell write snapshot exposes saveability");
         Assert (Shell.Write.Operation = Archive.Model.Current_Write_Generation (Model),
                 "ui shell write snapshot carries write operation generation");
      end;
      Archive.Model.Set_Selected_Count (Model, 0);
      Archive.Model.Clear_Pending_Writes (Model);
      Physical.Append (Fixture_Entry ("docs/guides/readme.txt"));
      Physical.Append (Fixture_Entry ("docs/notes.txt"));
      Physical.Append (Fixture_Entry ("zeta.txt"));
      Physical.Append (Fixture_Entry ("alpha.txt"));
      declare
         Build : constant Archive.Archives.Index.Build_Result :=
           Archive.Archives.Index.Build (Physical);
      begin
         Archive.Model.Publish_Archive_Index
           (Model, "sample.zip", Build.Index, Archive.Archives.Formats.Zip_Format);
         Archive.Model.Set_Source_Fingerprint
           (Model,
            (Status        => Archive.Source_Monitoring.Source_Ready,
             Size          => 42,
             Modified_Time => Ada.Calendar.Time_Of (2026, 7, 25)));
         Archive.Model.Set_Current_Directory (Model, 3);
         Archive.Model.Set_Focused_Entry (Model, 4);
         Archive.Model.Clear_Selection (Model);
         Assert
           (not Archive.Commands.Is_Enabled (Archive.Commands.Activate_Entry_Command, Model),
            "entry activation requires selection");
         Archive.Model.Select_Only (Model, 999);
         Assert
           (not Archive.Commands.Is_Enabled (Archive.Commands.Activate_Entry_Command, Model),
            "entry activation rejects invalid focused selection");
         Archive.Model.Select_Only (Model, 4);
         Assert
           (Archive.Commands.Is_Enabled (Archive.Commands.Activate_Entry_Command, Model),
            "entry activation accepts focused entry selection");
         declare
            Shell : constant Archive.UI.Shell_Snapshot :=
              Archive.UI.Build_Shell (Model, Config);
         begin
            Assert (Shell.Breadcrumb.Valid, "indexed ui shell has breadcrumb");
            Assert (Natural (Shell.Breadcrumb.Items.Length) = 3,
                    "ui shell breadcrumb includes ancestors");
            Assert
              (To_String (Shell.Breadcrumb.Items.Element (1).Name) = "/"
               and then To_String (Shell.Breadcrumb.Items.Element (2).Name) = "docs"
               and then To_String (Shell.Breadcrumb.Items.Element (3).Name) = "guides",
               "ui shell breadcrumb follows current directory");
            Assert (Natural (Shell.Content_Projection.Entries.Length) = 1,
                    "ui shell projects current directory children");
            Assert (Natural (Shell.Content_Rows.Length) = 1,
                    "ui shell materializes projected content row snapshots");
            Assert
              (To_String (Shell.Content_Rows.Element (1).Name) = "readme.txt"
               and then Shell.Content_Rows.Element (1).Entry_Id = 4,
               "ui shell content rows carry stable entry ids and display names");
            Assert (Shell.Content_Rows.Element (1).Selected,
                    "ui shell content rows carry selection state");
            Assert (Shell.Content_Rows.Element (1).Focused,
                    "ui shell content rows carry focus state");
            Assert
              (To_String (Shell.Content_Rows.Element (1).Accessible_Name) = "readme.txt"
               and then Ada.Strings.Fixed.Index
                 (To_String (Shell.Content_Rows.Element (1).Accessible_Description),
                  "selected") > 0,
               "ui shell rows carry accessible names and descriptions");
            Assert
              (Shell.Content_Rows.Element (1).Primary_Action =
                 Archive.Commands.Preview_Entry_Command
               and then Shell.Content_Rows.Element (1).Context_Command_Count >= 3,
               "ui shell rows expose primary and context actions");
            Assert
              (Shell.Content_View.Total_Rows = 1
               and then Shell.Content_View.Visible_First_Row = 1
               and then Shell.Content_View.Visible_Last_Row = 1,
               "ui shell content view exposes virtualized row window");
            Assert
              (Shell.Archive_Properties.Format = Archive.Archives.Formats.Zip_Format,
               "ui shell archive properties retain format");
            Assert (Shell.Archive_Properties.Entry_Count = 7,
                    "ui shell archive properties count index entries");
            Assert (Shell.Archive_Properties.Physical_Count = 4,
                    "ui shell archive properties count physical entries");
            Assert (Shell.Archive_Properties.Synthetic_Count = 3,
                    "ui shell archive properties count synthetic entries");
            Assert (Shell.Archive_Properties.Can_Verify_Payload,
                    "ui shell archive properties expose format capabilities");
            Assert (To_String (Shell.Source.Path) = "sample.zip",
                    "ui shell source snapshot carries source path");
            Assert (Shell.Source.Status = Archive.Source_Monitoring.Source_Ready,
                    "ui shell source snapshot carries source status");
            Assert (Shell.Source.Fingerprint.Size = 42,
                    "ui shell source snapshot carries fingerprint size");
            Assert
              (Archive.Model.Source_Changed
                 (Model,
                  (Status        => Archive.Source_Monitoring.Source_Ready,
                   Size          => 43,
                   Modified_Time => Ada.Calendar.Time_Of (2026, 7, 25))),
               "model detects changed source fingerprint");
            Assert (Shell.Entry_Properties.Id = 4,
                    "ui shell entry properties track focused entry");
            Assert (To_String (Shell.Entry_Properties.Name) = "readme.txt",
                    "ui shell entry properties expose focused display name");
            Assert (Shell.Entry_Properties.Can_Preview,
                    "ui shell entry properties expose preview availability");
            Assert (Shell.Selection.Count = 1
                    and then Shell.Selection.Items.Element (1) = 4
                    and then Shell.Selection.Anchor = 4,
                    "ui shell selection follows entry-id selection");
            Assert (Shell.Navigation.Current_Directory = 3,
                    "ui shell navigation tracks current directory");
            Assert (Shell.Navigation.Focused_Entry = 4,
                    "ui shell navigation tracks focused entry");
            Assert (Shell.Navigation.Can_Back, "ui shell navigation exposes back availability");
            Assert (Shell.Navigation.Can_Parent, "ui shell navigation exposes parent availability");
         end;

         declare
            Result : constant Archive.UI.Dispatch_Result :=
              Archive.UI.Dispatch_Command
                (Model, Archive.Commands.Navigate_Parent_Command, Archive.UI.Toolbar_Source);
         begin
            Assert (Result.Matched and then Result.Accepted, "parent navigation dispatch accepted");
            Assert (Archive.Model.Current_Directory (Model) = 2,
                    "parent navigation moves to parent directory");
         end;

         declare
            Result : constant Archive.UI.Dispatch_Result :=
              Archive.UI.Dispatch_Command
                (Model, Archive.Commands.Navigate_Back_Command, Archive.UI.Toolbar_Source);
         begin
            Assert (Result.Matched and then Result.Accepted, "back navigation dispatch accepted");
            Assert (Archive.Model.Current_Directory (Model) = 3,
                    "back navigation restores previous directory");
         end;

         declare
            Result : constant Archive.UI.Dispatch_Result :=
              Archive.UI.Dispatch_Command
                (Model, Archive.Commands.Navigate_Forward_Command, Archive.UI.Toolbar_Source);
         begin
            Assert (Result.Matched and then Result.Accepted, "forward navigation dispatch accepted");
            Assert (Archive.Model.Current_Directory (Model) = 2,
                    "forward navigation restores next directory");
         end;

         Archive.Model.Set_Current_Directory (Model, 3);
         Archive.Model.Start_Preview (Model, 4);
         declare
            Shell : constant Archive.UI.Shell_Snapshot :=
              Archive.UI.Build_Shell (Model, Config);
            Old_Generation : constant Archive.Types.Generation_Id :=
              Archive.Model.Current_Preview_Generation (Model) - 1;
            Preview_Result : constant Archive.Preview.Preview_Result :=
              (Kind       => Archive.Preview.Text_Preview,
               Text       => To_Unbounded_String ("hello"),
               Truncated  => False,
               Bytes_Used => 5,
               Trusted    => True);
         begin
            Assert (Shell.Preview_Panel.Phase = Archive.Model.Preview_Loading,
                    "preview panel tracks loading phase");
            Assert (Shell.Preview_Panel.Entry_Id = 4,
                    "preview panel tracks target entry");
            Assert
              (not Archive.Model.Publish_Preview
                 (Model, Old_Generation, Preview_Result),
               "model rejects stale preview generation");
            Assert
              (Archive.Model.Publish_Preview
                 (Model, Shell.Preview_Panel.Generation, Preview_Result),
               "model accepts current preview generation");
         end;
         declare
            Shell : constant Archive.UI.Shell_Snapshot :=
              Archive.UI.Build_Shell (Model, Config);
         begin
            Assert (Shell.Preview_Panel.Phase = Archive.Model.Preview_Ready,
                    "preview panel tracks ready phase");
            Assert (To_String (Shell.Preview_Panel.Result.Text) = "hello",
                    "preview panel carries bounded preview result");
         end;

         Archive.Model.Set_Current_Directory
           (Model, Archive.Archives.Index.Root_Id (Build.Index));
         Archive.Model.Set_Sorting
           (Model,
            Archive.View_Snapshots.Sort_By_Name,
            Archive.View_Snapshots.Ascending,
            Directories_First => True);
         Archive.Model.Set_Focused_Entry (Model, 2);
         declare
            Result : constant Archive.UI.Dispatch_Result :=
              Archive.UI.Dispatch_Shortcut
                (Model, Guikit.Input.Key_Down, Guikit.Input.No_Modifiers);
         begin
            Assert (Result.Matched and then Result.Accepted,
                    "content Down moves focus through projected rows");
            Assert (Archive.Model.Focused_Entry (Model) /= 2,
                    "content Down changes focused entry");
         end;
         declare
            Result : constant Archive.UI.Dispatch_Result :=
              Archive.UI.Dispatch_Shortcut
                (Model, Guikit.Input.Key_Home, Guikit.Input.No_Modifiers);
         begin
            Assert (Result.Matched and then Result.Accepted,
                    "content Home moves focus to first projected row");
            Assert (Archive.Model.Focused_Entry (Model) = 2,
                    "content Home focuses first row");
         end;
         declare
            Result : constant Archive.UI.Dispatch_Result :=
              Archive.UI.Dispatch_Shortcut
                (Model, Guikit.Input.Key_Space, Guikit.Input.No_Modifiers);
         begin
            Assert (Result.Matched and then Result.Accepted,
                    "content Space selects focused row");
            Assert (Archive.Model.Selected_Count (Model) = 1
                    and then Archive.Model.Selection_Anchor (Model) = 2,
                    "content Space updates entry-id selection");
         end;
         Archive.Model.Select_Only (Model, 2);
         declare
            Result : constant Archive.UI.Dispatch_Result :=
              Archive.UI.Dispatch_Shortcut
                (Model, Guikit.Input.Key_Return, Guikit.Input.No_Modifiers);
         begin
            Assert (Result.Matched and then Result.Accepted, "content Enter activates focused directory");
            Assert (Archive.Model.Current_Directory (Model) = 2,
                    "content Enter navigates to focused directory");
         end;

         Archive.Model.Select_Only (Model, 5);
         declare
            Result : constant Archive.UI.Dispatch_Result :=
              Archive.UI.Dispatch_Command
                (Model, Archive.Commands.Copy_Entry_Path_Command, Archive.UI.Toolbar_Source);
            Shell : constant Archive.UI.Shell_Snapshot :=
              Archive.UI.Build_Shell (Model, Config);
         begin
            Assert (Result.Matched and then Result.Accepted, "copy path dispatch accepted");
            Assert (Shell.Copy_Result.Kind = Archive.Model.Entry_Path_Copy,
                    "copy path records copy kind");
            Assert (To_String (Shell.Copy_Result.Text) = "docs/notes.txt",
                    "copy path records original archive path");
            Assert (Shell.Notification.Severity = Archive.Model.Info_Notification,
                    "copy path publishes info notification");
            Assert (To_String (Shell.Notification.Text) = "Copied entry information.",
                    "copy notification is localized");
         end;

         declare
            Result : constant Archive.UI.Dispatch_Result :=
              Archive.UI.Dispatch_Command
                (Model, Archive.Commands.Copy_Entry_Information_Command, Archive.UI.Toolbar_Source);
            Shell : constant Archive.UI.Shell_Snapshot :=
              Archive.UI.Build_Shell (Model, Config);
         begin
            Assert (Result.Matched and then Result.Accepted, "copy information dispatch accepted");
            Assert (Shell.Copy_Result.Kind = Archive.Model.Entry_Information_Copy,
                    "copy information records copy kind");
            Assert (Ada.Strings.Fixed.Index (To_String (Shell.Copy_Result.Text), "name=notes.txt") > 0,
                    "copy information includes display name");
         end;

         declare
            Result : constant Archive.UI.Dispatch_Result :=
              Archive.UI.Dispatch_Command
                (Model, Archive.Commands.Activate_Entry_Command, Archive.UI.Toolbar_Source);
         begin
            Assert (Result.Matched and then Result.Accepted, "file activation dispatch accepted");
            Assert (Archive.Model.Preview_Phase (Model) = Archive.Model.Preview_Loading,
                    "file activation starts preview");
            Assert (Archive.Model.Preview_Entry (Model) = 5,
                    "file activation targets focused entry");
         end;

         Archive.Model.Set_Current_Directory
           (Model, Archive.Archives.Index.Root_Id (Build.Index));
         Archive.Model.Set_Filter (Model, "notes");
         declare
            Shell : constant Archive.UI.Shell_Snapshot :=
              Archive.UI.Build_Shell (Model, Config);
         begin
            Assert (Natural (Shell.Content_Projection.Entries.Length) = 0,
                    "root projection filter does not include nested unmatched parents");
         end;
         Archive.Model.Set_Filter (Model, "");
         Archive.Model.Set_Sorting
           (Model,
            Archive.View_Snapshots.Sort_By_Name,
            Archive.View_Snapshots.Descending,
            Directories_First => False);
         declare
            Shell : constant Archive.UI.Shell_Snapshot :=
              Archive.UI.Build_Shell (Model, Config);
            First : constant Archive.Types.Entry_Id :=
              Shell.Content_Projection.Entries.Element (1);
         begin
            Assert (Shell.Content_View.Sort_Direction = Archive.View_Snapshots.Descending,
                    "ui shell content view tracks descending sort");
            Assert (not Shell.Content_View.Directories_First,
                    "ui shell content view tracks directories-first toggle");
            Assert
              (To_String (Archive.Archives.Index.Entry_For (Build.Index, First).Display_Name) =
               "zeta.txt",
               "ui shell projection honors model sort state");
         end;
      end;
      declare
         Result : constant Archive.UI.Dispatch_Result :=
           Archive.UI.Dispatch_Command
             (Model, Archive.Commands.Select_Details_View_Command, Archive.UI.Toolbar_Source);
      begin
         Assert (Result.Matched and then Result.Accepted, "details view dispatch executes");
         declare
            Shell : constant Archive.UI.Shell_Snapshot :=
              Archive.UI.Build_Shell (Model, Config);
         begin
            Assert (Shell.Content_View.Mode = Archive.Types.Details_View, "details dispatch updates shell mode");
            Assert (To_String (Shell.Content_View.Label) = "Details view", "details label is localized");
            Assert
              (To_String (Shell.Content_View.Accessible_Name) = "Archive contents details table",
               "details accessible name is localized");
            Assert (Shell.Content_View.Preferred_Row_H > 0, "details view has stable row height");
         end;
      end;

      declare
         Result : constant Archive.UI.Dispatch_Result :=
           Archive.UI.Dispatch_Command
             (Model, Archive.Commands.Change_Sorting_Command, Archive.UI.Toolbar_Source);
      begin
         Assert (Result.Matched and then Result.Accepted, "sort command dispatch accepted");
         Assert (Archive.Model.Sort_Direction (Model) = Archive.View_Snapshots.Ascending,
                 "sort command toggles model direction");
      end;

      declare
         Result : constant Archive.UI.Dispatch_Result :=
           Archive.UI.Dispatch_Command
             (Model, Archive.Commands.Select_Compact_View_Command, Archive.UI.Toolbar_Source);
      begin
         Assert (Result.Matched and then Result.Accepted, "compact view dispatch executes");
         declare
            Shell : constant Archive.UI.Shell_Snapshot :=
              Archive.UI.Build_Shell (Model, Config);
         begin
            Assert (Shell.Content_View.Mode = Archive.Types.Compact_View, "compact dispatch updates shell mode");
            Assert (To_String (Shell.Content_View.Label) = "Compact view", "compact label is localized");
         end;
      end;

      declare
         Result : constant Archive.UI.Dispatch_Result :=
           Archive.UI.Dispatch_Command
             (Model, Archive.Commands.Toggle_Preview_Command, Archive.UI.Toolbar_Source);
      begin
         Assert (Result.Matched and then Result.Accepted, "enabled toolbar dispatch executes command");
         Assert (Archive.Model.Preview_Visible (Model), "toolbar dispatch updates model through command");
      end;

      declare
         Mods : Guikit.Input.Modifier_Set := Guikit.Input.No_Modifiers;
      begin
         Mods (Guikit.Input.Control_Key) := True;
         declare
            Result : constant Archive.UI.Dispatch_Result :=
              Archive.UI.Dispatch_Shortcut (Model, Guikit.Input.Key_P, Mods);
         begin
            Assert (Result.Matched, "shortcut dispatch resolves registered shortcut");
            Assert
              (Archive.Model.Last_Command (Model) = Archive.Commands.Identifier
                 (Archive.Commands.Open_Command_Palette_Command),
               "shortcut dispatch routes through command executor");
         end;
      end;

      Archive.Model.Set_Command_Palette_Filter (Model, "verify");
      declare
         Shell : constant Archive.UI.Shell_Snapshot :=
           Archive.UI.Build_Shell (Model, Config);
      begin
         Assert (Shell.Overlay.Visible, "command palette overlay is visible");
         Assert (Shell.Overlay.Active = Archive.Model.Command_Palette_Overlay,
                 "command palette overlay is active");
         Assert (Shell.Overlay.Priority = 100, "overlay has high priority");
         Assert (Shell.Overlay.Escape_Closes, "overlay declares Escape handling");
         Assert (Shell.Focus.Region = Archive.Model.Command_Palette_Focus,
                 "command palette owns focus");
         Assert
           (To_String (Shell.Overlay.Accessible_Name) = "Command palette",
            "command palette overlay name is localized");
         Assert (Natural (Shell.Command_Palette.Rows.Length) = 1,
                 "ui shell command palette honors filter");
         Assert
           (Shell.Command_Palette.Rows.Element (1).Id = Archive.Commands.Verify_Archive_Command,
            "ui shell command palette exposes filtered command");
      end;
      Archive.Model.Set_Command_Palette_Filter (Model, "");

      declare
         Result : constant Archive.UI.Dispatch_Result :=
           Archive.UI.Dispatch_Shortcut
             (Model, Guikit.Input.Key_Escape, Guikit.Input.No_Modifiers);
      begin
         Assert (Result.Matched and then Result.Accepted, "Escape closes active overlay");
         declare
            Shell : constant Archive.UI.Shell_Snapshot :=
              Archive.UI.Build_Shell (Model, Config);
         begin
            Assert (not Shell.Overlay.Visible, "Escape hides overlay");
            Assert (Shell.Focus.Region = Archive.Model.Content_Focus,
                    "Escape restores content focus");
         end;
      end;

      declare
         Result : constant Archive.UI.Dispatch_Result :=
           Archive.UI.Dispatch_Command
             (Model, Archive.Commands.Open_Settings_Command, Archive.UI.Menu_Source);
      begin
         Assert (Result.Matched and then Result.Accepted, "settings dispatch opens overlay");
         declare
            Shell : constant Archive.UI.Shell_Snapshot :=
              Archive.UI.Build_Shell (Model, Config);
         begin
            Assert (Shell.Overlay.Active = Archive.Model.Settings_Overlay,
                    "settings overlay is active");
            Assert (Shell.Focus.Region = Archive.Model.Settings_Focus,
                    "settings overlay owns focus");
            Assert
              (To_String (Shell.Focus.Accessible_Name) = "Settings focus",
               "settings focus name is localized");
         end;
      end;

      declare
         Result : constant Archive.UI.Dispatch_Result :=
           Archive.UI.Dispatch_Command
             (Model, Archive.Commands.Verify_Archive_Command, Archive.UI.Menu_Source);
      begin
         Assert (Result.Matched and then Result.Accepted, "enabled menu dispatch executes command");
         Assert
           (Archive.Model.Last_Command (Model) =
              Archive.Commands.Identifier (Archive.Commands.Verify_Archive_Command),
            "menu dispatch records attempted command");
         declare
            Shell : constant Archive.UI.Shell_Snapshot :=
              Archive.UI.Build_Shell (Model, Config);
            Overlay : Archive.Verification.Overlays.Verification_Overlay :=
              Archive.Verification.Overlays.Empty
                (Archive.Model.Session_Generation (Model),
                 Shell.Verification.Operation_Generation,
                 Archive.Verification.Overlays.Verification_Completed);
         begin
            Assert (Shell.Verification.Phase = Archive.Verification.Overlays.Verification_Running,
                    "verify command starts verification snapshot");
            Archive.Verification.Overlays.Set_Result
              (Overlay, 5, Archive.Archives.Entries.Verified, "ok");
            Assert
              (Archive.Model.Publish_Verification (Model, Overlay) =
               Archive.Verification.Overlays.Overlay_Accepted,
               "current verification overlay is accepted");
         end;
         declare
            Shell : constant Archive.UI.Shell_Snapshot :=
              Archive.UI.Build_Shell (Model, Config);
         begin
            Assert (Shell.Verification.Phase = Archive.Verification.Overlays.Verification_Completed,
                    "ui shell verification tracks completed phase");
            Assert (Shell.Verification.Entry_Count = 1,
                    "ui shell verification reports retained entry result count");
            Assert (Shell.Status_Bar.Verification_Count = 1,
                    "status bar mirrors verification entry count");
         end;
      end;

      Archive.Model.Close_Dialog (Model);
      declare
         Result : constant Archive.UI.Dispatch_Result :=
           Archive.UI.Dispatch_Command
             (Model, Archive.Commands.Add_Files_Command, Archive.UI.Toolbar_Source);
      begin
         Assert (Result.Matched and then Result.Accepted, "add files dispatch accepted");
         declare
            Shell : constant Archive.UI.Shell_Snapshot :=
              Archive.UI.Build_Shell (Model, Config);
         begin
            Assert (Shell.Dialog.Active = Archive.Model.Add_Files_Dialog,
                    "add files dialog active");
            Assert (To_String (Shell.Dialog.Title) = "Add files",
                    "add files dialog title is localized");
            Assert (Shell.Write.Change_Count = 0,
                    "add files waits for host-source payload before planning writes");
         end;
      end;

      Archive.Model.Close_Dialog (Model);
      declare
         Result : constant Archive.UI.Dispatch_Result :=
           Archive.UI.Dispatch_Command
             (Model, Archive.Commands.Add_Directory_Command, Archive.UI.Toolbar_Source);
      begin
         Assert (Result.Matched and then Result.Accepted, "add directory dispatch accepted");
         declare
            Shell : constant Archive.UI.Shell_Snapshot :=
              Archive.UI.Build_Shell (Model, Config);
         begin
            Assert (Shell.Dialog.Active = Archive.Model.Add_Directory_Dialog,
                    "add directory dialog active");
            Assert (To_String (Shell.Dialog.Title) = "Add directory",
                    "add directory dialog title is localized");
         end;
      end;

      Archive.Model.Close_Dialog (Model);
      Archive.Model.Select_Only (Model, 5);
      declare
         Result : constant Archive.UI.Dispatch_Result :=
           Archive.UI.Dispatch_Command
             (Model, Archive.Commands.Replace_Selected_Command, Archive.UI.Context_Menu_Source);
      begin
         Assert (Result.Matched and then Result.Accepted, "replace dispatch accepted");
         declare
            Shell : constant Archive.UI.Shell_Snapshot :=
              Archive.UI.Build_Shell (Model, Config);
         begin
            Assert (Shell.Dialog.Active = Archive.Model.Replace_File_Dialog,
                    "replace dialog active");
            Assert (To_String (Shell.Dialog.Title) = "Replace file",
                    "replace dialog title is localized");
         end;
      end;

      Archive.Model.Close_Dialog (Model);
      declare
         Result : constant Archive.UI.Dispatch_Result :=
           Archive.UI.Dispatch_Command
             (Model, Archive.Commands.Rename_Selected_Command, Archive.UI.Context_Menu_Source);
      begin
         Assert (Result.Matched and then Result.Accepted, "rename dispatch accepted");
         declare
            Shell : constant Archive.UI.Shell_Snapshot :=
              Archive.UI.Build_Shell (Model, Config);
         begin
            Assert (Shell.Dialog.Active = Archive.Model.Rename_Entry_Dialog,
                    "rename dialog active");
            Assert (To_String (Shell.Dialog.Title) = "Rename entry",
                    "rename dialog title is localized");
         end;
      end;

      declare
         Result : constant Archive.UI.Dispatch_Result :=
           Archive.UI.Dispatch_Command
             (Model, Archive.Commands.Extract_All_Command, Archive.UI.Menu_Source);
      begin
         Assert (Result.Matched and then Result.Accepted, "extract all dispatch accepted");
         declare
            Shell : constant Archive.UI.Shell_Snapshot :=
              Archive.UI.Build_Shell (Model, Config);
         begin
            Assert (Shell.Dialog.Active = Archive.Model.Extract_Destination_Dialog,
                    "extract destination dialog active");
            Assert
              (To_String (Shell.Dialog.Title) = "Choose extraction destination",
               "extract destination dialog title is localized");
            Assert (Shell.Extraction.Phase = Archive.Model.Extraction_Planned,
                    "extract all command publishes extraction plan");
            Assert (Shell.Extraction.Session = Archive.Model.Session_Generation (Model),
                    "extraction plan is tied to current session");
            Assert (Shell.Extraction.Requested_Count = 4,
                    "extract all plan requests physical archive entries only");
            Assert (Shell.Extraction.Entry_Count = 4,
                    "extract all plan excludes synthetic virtual directories");
         end;
      end;

      declare
         Result : constant Archive.UI.Dispatch_Result :=
           Archive.UI.Dispatch_Command
             (Model, Archive.Commands.Cancel_Extraction_Command, Archive.UI.Toolbar_Source);
      begin
         Assert (Result.Matched and then Result.Accepted, "cancel extraction dispatch accepted");
         declare
            Shell : constant Archive.UI.Shell_Snapshot :=
              Archive.UI.Build_Shell (Model, Config);
         begin
            Assert (Shell.Extraction.Phase = Archive.Model.No_Extraction,
                    "cancel extraction clears planned state");
            Assert (Shell.Extraction.Entry_Count = 0,
                    "cancel extraction clears plan entries");
         end;
      end;

      Archive.Model.Close_Dialog (Model);
      Archive.Model.Select_Only (Model, 5);
      declare
         Result : constant Archive.UI.Dispatch_Result :=
           Archive.UI.Dispatch_Command
             (Model, Archive.Commands.Show_Archive_Properties_Command, Archive.UI.Menu_Source);
      begin
         Assert (Result.Matched and then Result.Accepted, "archive properties dispatch accepted");
         declare
            Shell : constant Archive.UI.Shell_Snapshot :=
              Archive.UI.Build_Shell (Model, Config);
         begin
            Assert (Shell.Dialog.Active = Archive.Model.Archive_Properties_Dialog,
                    "archive properties dialog active");
            Assert (To_String (Shell.Dialog.Title) = "Archive properties",
                    "archive properties dialog title is localized");
         end;
      end;

      Archive.Model.Close_Dialog (Model);
      declare
         Result : constant Archive.UI.Dispatch_Result :=
           Archive.UI.Dispatch_Command
             (Model, Archive.Commands.Show_Entry_Properties_Command, Archive.UI.Menu_Source);
      begin
         Assert (Result.Matched and then Result.Accepted, "entry properties dispatch accepted");
         declare
            Shell : constant Archive.UI.Shell_Snapshot :=
              Archive.UI.Build_Shell (Model, Config);
         begin
            Assert (Shell.Dialog.Active = Archive.Model.Entry_Properties_Dialog,
                    "entry properties dialog active");
            Assert (To_String (Shell.Dialog.Title) = "Entry properties",
                    "entry properties dialog title is localized");
         end;
      end;

      Archive.Model.Close_Dialog (Model);
      declare
         Unsaved : Archive.Model.Application_Model;
      begin
         Archive.Model.Initialize (Unsaved);
         Archive.Model.Create_New_Archive (Unsaved);
         declare
            Result : constant Archive.UI.Dispatch_Result :=
              Archive.UI.Dispatch_Command
                (Unsaved, Archive.Commands.Save_Archive_Command, Archive.UI.Toolbar_Source);
         begin
            Assert (Result.Matched and then Result.Accepted, "save dispatch accepted");
            declare
               Shell : constant Archive.UI.Shell_Snapshot :=
                 Archive.UI.Build_Shell (Unsaved, Config);
            begin
               Assert (Shell.Dialog.Active = Archive.Model.Save_As_Dialog,
                       "save on unsaved archive opens save-as dialog");
               Assert (Shell.Write.Has_Pending,
                       "save-as prompt preserves pending new archive write");
            end;
         end;
      end;

      Archive.Model.Plan_Add_File (Model, "host/fail.txt", "docs/fail.txt");
      Archive.Model.Begin_Save (Model);
      Assert
        (Archive.Model.Publish_Write_Result
           (Model, Archive.Model.Current_Save_Generation (Model), Success => False),
         "save failure snapshot uses an active save completion");
      declare
         Shell : constant Archive.UI.Shell_Snapshot :=
           Archive.UI.Build_Shell (Model, Config);
      begin
         Assert (Shell.Notification.Severity = Archive.Model.Error_Notification,
                 "save failure notification is error");
         Assert (To_String (Shell.Notification.Text) = "Archive save failed.",
                 "save failure notification is localized");
      end;

      declare
         Quit_Model : Archive.Model.Application_Model;
         Result     : Archive.UI.Dispatch_Result;
      begin
         Archive.Model.Initialize (Quit_Model);
         Result :=
           Archive.UI.Dispatch_Command
             (Quit_Model, Archive.Commands.Quit_Command, Archive.UI.Menu_Source);
         Assert (Result.Matched and then Result.Accepted, "quit dispatch accepted");
         declare
            Shell : constant Archive.UI.Shell_Snapshot :=
              Archive.UI.Build_Shell (Quit_Model, Config);
         begin
            Assert (Shell.Lifecycle = Archive.Model.Shutting_Down,
                    "quit dispatch enters shutdown lifecycle");
            Assert (Shell.Lifecycle_Request.Request = Archive.Model.Quit_Request,
                    "quit dispatch records lifecycle request");
         end;
      end;
   end Test_UI_Shell;

   procedure Test_GUI_Frame (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      Model  : Archive.Model.Application_Model;
      Physical : Archive.Archives.Entries.Entry_Vectors.Vector;
      Config : constant Archive.UI.Shell_Configuration :=
        (Width => 1000,
         Height => 700,
         Locale => To_Unbounded_String ("en"),
         Line_Height => 20);

      function Has_Text (Frame : Archive.GUI_Frame.Frame; Text : String) return Boolean is
      begin
         for Line of Frame.Text loop
            if Ada.Strings.Fixed.Index (To_String (Line.Text), Text) > 0 then
               return True;
            end if;
         end loop;
         for Line of Frame.Overlay_Text loop
            if Ada.Strings.Fixed.Index (To_String (Line.Text), Text) > 0 then
               return True;
            end if;
         end loop;
         return False;
      end Has_Text;
   begin
      Archive.Model.Initialize (Model);
      declare
         Shell      : constant Archive.UI.Shell_Snapshot := Archive.UI.Build_Shell (Model, Config);
         Frame      : constant Archive.GUI_Frame.Frame := Archive.GUI_Frame.Build (Shell);
         Check      : constant Archive.GUI_Frame.Frame_Validation := Archive.GUI_Frame.Validate (Frame);
         Submission : constant Guikit.Vulkan.Submission_Batch := Archive.GUI_Frame.To_Submission (Frame);
      begin
         Assert (Check.Valid, "gui frame validates rendered shell draw commands");
         Assert (Check.Rectangle_Count >= 5, "gui frame emits structural rectangles");
         Assert (Check.Text_Count >= 4, "gui frame emits text commands");
         Assert (Check.Accessibility_Count >= 4, "gui frame emits accessibility nodes");
         Assert (Check.Vertex_Count = Natural (Submission.Vertices.Length),
                 "gui frame validation counts Vulkan submission vertices");
         Assert (Submission.Rectangle_Vertex_Count > 0,
                 "gui frame produces Vulkan rectangle vertices");
      end;

      Physical.Append (Fixture_Entry ("docs/readme.txt"));
      Physical.Append (Fixture_Entry ("image.png"));
      declare
         Build : constant Archive.Archives.Index.Build_Result :=
           Archive.Archives.Index.Build (Physical);
      begin
         Archive.Model.Publish_Archive_Index
           (Model, "sample.zip", Build.Index, Archive.Archives.Formats.Zip_Format);
         Archive.Model.Select_Only (Model, 2);
         Archive.Model.Start_Preview (Model, 2);
         declare
            Accepted : constant Boolean := Archive.Model.Publish_Preview
              (Model,
               Archive.Model.Current_Preview_Generation (Model),
               (Kind       => Archive.Preview.Text_Preview,
                Text       => To_Unbounded_String ("preview text"),
                Truncated  => False,
                Bytes_Used => 12,
                Trusted    => True));
         begin
            Assert (Accepted, "gui frame test publishes current preview result");
         end;
         declare
            Shell : constant Archive.UI.Shell_Snapshot := Archive.UI.Build_Shell (Model, Config);
            Frame : constant Archive.GUI_Frame.Frame := Archive.GUI_Frame.Build (Shell);
            Check : constant Archive.GUI_Frame.Frame_Validation := Archive.GUI_Frame.Validate (Frame);
         begin
            Assert (Check.Valid, "gui frame validates populated content grid");
            Assert (Has_Text (Frame, "docs"), "gui frame renders projected archive entries");
            Assert (Has_Text (Frame, "preview text"),
                    "gui frame renders preview panel rows through guikit list panel");
            Assert (Natural (Frame.Accessibility.Length) >= 5,
                    "gui frame emits accessibility for content rows");
         end;

         Archive.Model.Open_Command_Palette (Model);
         declare
            Shell : constant Archive.UI.Shell_Snapshot := Archive.UI.Build_Shell (Model, Config);
            Frame : constant Archive.GUI_Frame.Frame := Archive.GUI_Frame.Build (Shell);
            Check : constant Archive.GUI_Frame.Frame_Validation := Archive.GUI_Frame.Validate (Frame);
         begin
            Assert (Check.Valid, "gui frame validates guikit command palette overlay");
            Assert (Natural (Frame.Overlay_Rectangles.Length) > 1,
                    "gui frame command palette emits guikit overlay rectangles");
            Assert (Has_Text (Frame, "Command palette"),
                    "gui frame command palette renders localized overlay title");
         end;

         Archive.Model.Open_Settings (Model);
         declare
            Shell : constant Archive.UI.Shell_Snapshot := Archive.UI.Build_Shell (Model, Config);
            Frame : constant Archive.GUI_Frame.Frame := Archive.GUI_Frame.Build (Shell);
            Check : constant Archive.GUI_Frame.Frame_Validation := Archive.GUI_Frame.Validate (Frame);
         begin
            Assert (Check.Valid, "gui frame validates guikit settings overlay");
            Assert (Has_Text (Frame, "Settings"),
                    "gui frame settings overlay renders localized title");
            Assert (Has_Text (Frame, "Default view"),
                    "gui frame settings overlay renders localized fields");
         end;
      end;

      Archive.Model.Open_Dialog (Model, Archive.Model.Open_Archive_Dialog);
      declare
         Frame : constant Archive.GUI_Frame.Frame :=
           Archive.GUI_Frame.Build (Archive.UI.Build_Shell (Model, Config));
         Check : constant Archive.GUI_Frame.Frame_Validation := Archive.GUI_Frame.Validate (Frame);
      begin
         Assert (Check.Valid, "gui frame validates dialog overlay draw commands");
         Assert (Natural (Frame.Overlay_Rectangles.Length) > 0,
                 "gui frame emits overlay rectangles for dialogs");
         Assert (Natural (Frame.Overlay_Text.Length) > 0,
                 "gui frame emits overlay text for dialogs");
      end;
   end Test_GUI_Frame;

   procedure Test_GUI_Runtime (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      Runtime : Archive.GUI_Runtime.Runtime_State;
      Root    : constant String := "obj/gui-runtime-open-test";
      Zip_Path : constant String := Root & "/sample.zip";
      Save_Path : constant String := Root & "/saved.zip";
      Extract_Root : constant String := Root & "/out";
   begin
      if not Ada.Directories.Exists (Root) then
         Ada.Directories.Create_Path (Root);
      end if;
      Write_Bytes (Zip_Path, One_File_Zip);
      if not Ada.Directories.Exists (Extract_Root) then
         Ada.Directories.Create_Path (Extract_Root);
      end if;
      if Ada.Directories.Exists (Save_Path) then
         Ada.Directories.Delete_File (Save_Path);
      end if;

      Archive.GUI_Runtime.Initialize (Runtime, Locale => "en", Width => 1024, Height => 720);
      declare
         Validation : constant Archive.GUI_Runtime.Validation_Result :=
           Archive.GUI_Runtime.Validate (Runtime);
         Shell      : constant Archive.UI.Shell_Snapshot :=
           Archive.GUI_Runtime.Snapshot (Runtime);
         Frame      : constant Archive.GUI_Frame.Frame := Archive.GUI_Runtime.Render_Frame (Runtime);
         Frame_Check : constant Archive.GUI_Frame.Frame_Validation := Archive.GUI_Frame.Validate (Frame);
      begin
         Assert (Validation.Ready, "gui runtime validates initial guikit shell");
         Assert (To_String (Validation.Reason_Key) = "runtime.ready",
                 "gui runtime reports stable ready reason");
         Assert (To_String (Shell.Title) = "archive", "gui runtime builds localized shell title");
         Assert (Shell.Layout.Content_W > 0 and then Shell.Layout.Content_H > 0,
                 "gui runtime builds non-empty content layout");
         Assert (Natural (Shell.Menus.Sections.Length) > 0, "gui runtime exposes menus");
         Assert (Natural (Shell.Toolbar.Commands.Length) > 0, "gui runtime exposes toolbar commands");
         Assert (Frame_Check.Valid, "gui runtime renders a valid guikit frame");
         Assert (Frame_Check.Vertex_Count > 0, "gui runtime frame has Vulkan submission vertices");
      end;

      Archive.GUI_Runtime.Resize (Runtime, Width => 900, Height => 600);
      declare
         Shell : constant Archive.UI.Shell_Snapshot := Archive.GUI_Runtime.Snapshot (Runtime);
      begin
         Assert (Shell.Layout.Content_W + Shell.Layout.Preview_W = 900,
                 "gui runtime resize updates guikit layout width");
         Assert (Shell.Layout.Status_Y + Shell.Layout.Status_H = 600,
                 "gui runtime resize updates status bar position");
      end;

      declare
         Result : constant Archive.UI.Dispatch_Result :=
           Archive.GUI_Runtime.Dispatch_Command
             (Runtime, Archive.Commands.Open_Archive_Command, Archive.UI.Toolbar_Source);
      begin
         Assert (Result.Matched and then Result.Accepted,
                 "gui runtime dispatch opens archive dialog");
         Assert (Archive.GUI_Runtime.Snapshot (Runtime).Dialog.Active =
                   Archive.Model.Open_Archive_Dialog,
                 "gui runtime exposes open dialog before completion");
      end;

      Archive.GUI_Runtime.Complete_Open_Dialog (Runtime, Zip_Path);
      Assert (Archive.GUI_Runtime.Open_Operation_Status (Runtime) =
              Archive.Operations.Opening.Operation_Running,
              "gui runtime dialog completion starts background open through operation coordinator");
      Assert (not Archive.GUI_Runtime.Snapshot (Runtime).Dialog.Visible,
              "gui runtime open dialog completion closes modal dialog");
      declare
         Drain : Archive.Operations.Opening.Drain_Result;
      begin
         for Attempt in 1 .. 10_000 loop
            Drain := Archive.GUI_Runtime.Drain_Operations (Runtime);
            exit when Drain.Event_Seen;
         end loop;
         Assert
           (Drain.Event_Seen and then Drain.Applied
            and then Drain.Status = Archive.Operations.Opening.Operation_Completed,
            "gui runtime drains open completion and publishes prepared archive");
         Assert
           (Archive.GUI_Runtime.Snapshot (Runtime).Source.Path = To_Unbounded_String (Zip_Path),
            "gui runtime snapshot reflects opened archive source");
         declare
            Report : constant String := Archive.GUI_Runtime.Runtime_Report (Runtime);
         begin
            Assert (Ada.Strings.Fixed.Index (Report, "open_status=OPERATION_COMPLETED") > 0,
                    "gui runtime report includes completed open operation status");
            Assert (Ada.Strings.Fixed.Index (Report, "source=" & Zip_Path) > 0,
                    "gui runtime report includes opened archive source path");
         end;
      end;

      declare
         Result : constant Archive.UI.Dispatch_Result :=
           Archive.GUI_Runtime.Dispatch_Command
             (Runtime, Archive.Commands.Open_Command_Palette_Command, Archive.UI.Shortcut_Source);
      begin
         Assert (Result.Matched and then Result.Accepted,
                 "gui runtime dispatches commands through central executor");
         Assert (Archive.GUI_Runtime.Snapshot (Runtime).Overlay.Active =
                   Archive.Model.Command_Palette_Overlay,
                 "gui runtime command dispatch mutates model-owned overlay");
      end;

      declare
         Result : constant Archive.UI.Dispatch_Result :=
           Archive.GUI_Runtime.Execute_Palette_Command
             (Runtime,
              Archive.Commands.Identifier (Archive.Commands.Verify_Archive_Command));
         Shell : constant Archive.UI.Shell_Snapshot := Archive.GUI_Runtime.Snapshot (Runtime);
      begin
         Assert (Result.Matched and then Result.Accepted,
                 "gui runtime executes command palette command by stable id");
         Assert (not Shell.Overlay.Visible,
                 "accepted palette command closes command palette overlay");
         Assert (Shell.Focus.Region = Archive.Model.Content_Focus,
                 "palette command completion restores content focus");
         Assert (Shell.Verification.Phase = Archive.Verification.Overlays.Verification_Running,
                 "palette command dispatch starts verification through central executor");
      end;

      declare
         Before : constant Archive.UI.Shell_Snapshot := Archive.GUI_Runtime.Snapshot (Runtime);
         Result : constant Archive.UI.Dispatch_Result :=
           Archive.GUI_Runtime.Dispatch_Command
             (Runtime, Archive.Commands.Toggle_Preview_Command, Archive.UI.Menu_Source);
         After : constant Archive.UI.Shell_Snapshot := Archive.GUI_Runtime.Snapshot (Runtime);
      begin
         Assert (Result.Matched and then Result.Accepted,
                 "gui runtime toggles preview through central executor");
         Assert
           (After.Preview_Visible /= Before.Preview_Visible
            and then After.Preview_Panel.Visible = After.Preview_Visible,
            "gui runtime preview toggle updates shell and preview panel together");
      end;

      declare
         Result : constant Archive.UI.Dispatch_Result :=
           Archive.GUI_Runtime.Dispatch_Command
             (Runtime, Archive.Commands.Open_Settings_Command, Archive.UI.Menu_Source);
      begin
         Assert (Result.Matched and then Result.Accepted,
                 "gui runtime opens settings overlay through central executor");
         Assert
           (Archive.GUI_Runtime.Snapshot (Runtime).Overlay.Active =
              Archive.Model.Settings_Overlay,
            "gui runtime settings command publishes model-owned settings overlay");
      end;

      declare
         Result : constant Archive.UI.Dispatch_Result :=
           Archive.GUI_Runtime.Dispatch_Shortcut
             (Runtime, Guikit.Input.Key_Escape, Guikit.Input.No_Modifiers);
      begin
         Assert (Result.Matched and then Result.Accepted,
                 "gui runtime Escape closes settings overlay");
         Assert (not Archive.GUI_Runtime.Snapshot (Runtime).Overlay.Visible,
                 "gui runtime settings overlay is dismissed through keyboard dispatch");
      end;

      declare
         Result : constant Archive.UI.Dispatch_Result :=
           Archive.GUI_Runtime.Execute_Palette_Command (Runtime, "missing.command");
         Shell : constant Archive.UI.Shell_Snapshot := Archive.GUI_Runtime.Snapshot (Runtime);
      begin
         Assert (not Result.Matched and then not Result.Accepted,
                 "gui runtime rejects unknown palette command ids");
         Assert (Shell.Notification.Severity = Archive.Model.Warning_Notification,
                 "unknown palette command publishes warning notification");
      end;

      declare
         Result : constant Archive.UI.Dispatch_Result :=
           Archive.GUI_Runtime.Dispatch_Command
             (Runtime, Archive.Commands.Add_Files_Command, Archive.UI.Toolbar_Source);
      begin
         Assert (Result.Matched and then Result.Accepted,
                 "gui runtime add-files command opens dialog");
         Assert (Archive.GUI_Runtime.Snapshot (Runtime).Dialog.Active =
                   Archive.Model.Add_Files_Dialog,
                 "gui runtime exposes add-files dialog before completion");
      end;
      Archive.GUI_Runtime.Complete_Add_File_Dialog
        (Runtime, Zip_Path, "docs/readme.zip");
      declare
         Shell : constant Archive.UI.Shell_Snapshot := Archive.GUI_Runtime.Snapshot (Runtime);
      begin
         Assert (not Shell.Dialog.Visible,
                 "gui runtime add-files completion closes dialog");
         Assert (Shell.Write.Has_Pending and then Shell.Write.Saveable,
                 "gui runtime add-files completion publishes saveable write plan");
         Assert (Shell.Status_Bar.Has_Pending_Writes,
                 "runtime status bar reflects dialog-completed write plan");
      end;

      declare
         Result : constant Archive.UI.Dispatch_Result :=
           Archive.GUI_Runtime.Dispatch_Command
             (Runtime, Archive.Commands.Save_Archive_As_Command, Archive.UI.Menu_Source);
      begin
         Assert (Result.Matched and then Result.Accepted,
                 "gui runtime save-as command opens dialog");
         Assert (Archive.GUI_Runtime.Snapshot (Runtime).Dialog.Active =
                   Archive.Model.Save_As_Dialog,
                 "gui runtime exposes save-as dialog before completion");
      end;
      declare
         Save : constant Archive.Writes.Service.Save_Result :=
           Archive.GUI_Runtime.Complete_Save_As_Dialog
             (Runtime,
              Save_Path,
              Method    => Archive.Writes.Dispatch.Zip_Stored_Method,
              Overwrite => True);
         Shell : constant Archive.UI.Shell_Snapshot := Archive.GUI_Runtime.Snapshot (Runtime);
      begin
         Assert (Save.Status = Archive.Writes.Service.Save_Completed,
                 "gui runtime save-as completion publishes archive through save service: "
                 & Archive.Writes.Service.Save_Status'Image (Save.Status)
                 & " payload=" & Archive.Archives.Errors.Error_Code'Image (Save.Payload_Status)
                 & " publish=" & Archive.Writes.Results.Write_Status'Image (Save.Publish_Status));
         Assert (not Shell.Dialog.Visible,
                 "successful runtime save-as completion closes dialog");
         Assert (not Shell.Write.Has_Pending,
                 "successful runtime save-as completion clears pending writes");
         Assert (Shell.Source.Path = To_Unbounded_String (Save_Path),
                 "successful runtime save-as publishes saved archive as active source");
         Assert (Ada.Directories.Exists (Save_Path),
                 "runtime save-as completion creates target archive");
      end;

      declare
         Result : Archive.UI.Dispatch_Result;
      begin
         Result := Archive.GUI_Runtime.Dispatch_Shortcut
           (Runtime, Guikit.Input.Key_Home, Guikit.Input.No_Modifiers);
         Assert (Result.Matched and then Result.Accepted,
                 "gui runtime content Home focuses first row");
         Result := Archive.GUI_Runtime.Dispatch_Shortcut
           (Runtime, Guikit.Input.Key_Return, Guikit.Input.No_Modifiers);
         Assert (Result.Matched and then Result.Accepted,
                 "gui runtime content Return opens focused directory");
         Result := Archive.GUI_Runtime.Dispatch_Shortcut
           (Runtime, Guikit.Input.Key_Home, Guikit.Input.No_Modifiers);
         Assert (Result.Matched and then Result.Accepted,
                 "gui runtime content Home focuses first child row");
         Result := Archive.GUI_Runtime.Dispatch_Shortcut
           (Runtime, Guikit.Input.Key_Space, Guikit.Input.No_Modifiers);
         Assert (Result.Matched and then Result.Accepted,
                 "gui runtime content Space selects first file row");
         Assert (Archive.GUI_Runtime.Snapshot (Runtime).Selection.Count = 1,
                 "gui runtime keyboard selection updates snapshot");
      end;

      declare
         Result : constant Archive.UI.Dispatch_Result :=
           Archive.GUI_Runtime.Dispatch_Command
             (Runtime, Archive.Commands.Replace_Selected_Command, Archive.UI.Context_Menu_Source);
      begin
         Assert (Result.Matched and then Result.Accepted,
                 "gui runtime replace command opens dialog");
         Assert (Archive.GUI_Runtime.Snapshot (Runtime).Dialog.Active =
                   Archive.Model.Replace_File_Dialog,
                 "gui runtime exposes replace dialog before completion");
      end;
      Archive.GUI_Runtime.Complete_Replace_File_Dialog (Runtime, Zip_Path);
      Assert (Archive.GUI_Runtime.Snapshot (Runtime).Write.Saveable,
              "gui runtime replace completion publishes saveable write plan");
      declare
         Result : constant Archive.UI.Dispatch_Result :=
           Archive.GUI_Runtime.Dispatch_Command
             (Runtime, Archive.Commands.Discard_Changes_Command, Archive.UI.Toolbar_Source);
      begin
         Assert (Result.Matched and then Result.Accepted,
                 "gui runtime discard clears replace write plan");
      end;

      declare
         Result : constant Archive.UI.Dispatch_Result :=
           Archive.GUI_Runtime.Dispatch_Command
             (Runtime, Archive.Commands.Rename_Selected_Command, Archive.UI.Context_Menu_Source);
      begin
         Assert (Result.Matched and then Result.Accepted,
                 "gui runtime rename command opens dialog");
         Assert (Archive.GUI_Runtime.Snapshot (Runtime).Dialog.Active =
                   Archive.Model.Rename_Entry_Dialog,
                 "gui runtime exposes rename dialog before completion");
      end;
      Archive.GUI_Runtime.Complete_Rename_Dialog (Runtime, "renamed-a.txt");
      Assert (Archive.GUI_Runtime.Snapshot (Runtime).Write.Saveable,
              "gui runtime rename completion publishes saveable write plan");
      declare
         Result : constant Archive.UI.Dispatch_Result :=
           Archive.GUI_Runtime.Dispatch_Command
             (Runtime, Archive.Commands.Discard_Changes_Command, Archive.UI.Toolbar_Source);
      begin
         Assert (Result.Matched and then Result.Accepted,
                 "gui runtime discard command clears dialog-completed write plan");
      end;

      declare
         Result : constant Archive.UI.Dispatch_Result :=
           Archive.GUI_Runtime.Dispatch_Command
             (Runtime, Archive.Commands.Extract_Selected_Command, Archive.UI.Toolbar_Source);
      begin
         Assert (Result.Matched and then Result.Accepted,
                 "gui runtime extract-selected command opens destination dialog");
         Assert (Archive.GUI_Runtime.Snapshot (Runtime).Dialog.Active =
                   Archive.Model.Extract_Destination_Dialog,
                 "gui runtime exposes extraction dialog before completion");
      end;
      declare
         Extract : constant Archive.Extraction.Service.Extract_Result :=
           Archive.GUI_Runtime.Complete_Extraction_Dialog
             (Runtime, Extract_Root, Overwrite => True);
         Shell : constant Archive.UI.Shell_Snapshot := Archive.GUI_Runtime.Snapshot (Runtime);
      begin
         Assert (Extract.Status = Archive.Extraction.Service.Extract_Completed,
                 "gui runtime extraction dialog completion executes extraction service");
         Assert (not Shell.Dialog.Visible,
                 "successful runtime extraction completion closes destination dialog");
         Assert (Shell.Extraction.Last_Status = Archive.Extraction.Results.Completed,
                 "runtime extraction result is reflected in shell snapshot");
         Assert (Extract.Completed_Count = 1,
                 "runtime extraction completion reports selected entry count");
      end;

      declare
         Result : constant Archive.UI.Dispatch_Result :=
           Archive.GUI_Runtime.Dispatch_Command
             (Runtime, Archive.Commands.Open_Command_Palette_Command, Archive.UI.Shortcut_Source);
      begin
         Assert (Result.Matched and then Result.Accepted,
                 "gui runtime reopens command palette for Escape dispatch");
      end;

      declare
         Result : constant Archive.UI.Dispatch_Result :=
           Archive.GUI_Runtime.Dispatch_Shortcut
             (Runtime, Guikit.Input.Key_Escape, Guikit.Input.No_Modifiers);
      begin
         Assert (Result.Matched and then Result.Accepted,
                 "gui runtime dispatches keyboard through shell input handler");
         Assert (not Archive.GUI_Runtime.Snapshot (Runtime).Overlay.Visible,
                 "gui runtime shortcut closes overlay");
      end;

      Archive.GUI_Runtime.Request_Close (Runtime);
      Assert (Archive.GUI_Runtime.Snapshot (Runtime).Lifecycle = Archive.Model.Shutting_Down,
              "gui runtime close request enters shutdown lifecycle");
      declare
         Report : constant String := Archive.Application.Headless_GUI_Report;
      begin
         Assert (Ada.Strings.Fixed.Index (Report, "archive gui runtime: ready=TRUE") > 0,
                 "application exposes headless gui runtime report");
         Assert (Ada.Strings.Fixed.Index (Report, "vertices=") > 0,
                 "headless gui report includes frame vertex count");
      end;
      declare
         Report : constant String := Archive.Application.Headless_GUI_Report
           (Initial_Path => Zip_Path);
      begin
         Assert (Ada.Strings.Fixed.Index (Report, "open_status=OPERATION_COMPLETED") > 0,
                 "headless gui report drains startup archive open completion");
         Assert (Ada.Strings.Fixed.Index (Report, "source=" & Zip_Path) > 0,
                 "headless gui report accepts startup archive path");
         Assert (Ada.Strings.Fixed.Index (Report, "recent= 1") > 0,
                 "headless gui report exposes recent archive count");
      end;
   end Test_GUI_Runtime;

   procedure Test_Live_Runtime (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      Args : Archive.Application.String_Vectors.Vector;
   begin
      Args.Append (To_Unbounded_String ("--live-smoke"));
      declare
         Config : constant Archive.Application.Run_Configuration :=
           Archive.Application.Parse_Run_Configuration (Args);
      begin
         Assert (Config.Mode = Archive.Application.Live_Smoke_Run,
                 "application parser exposes bounded live smoke mode");
      end;

      declare
         Caps : constant Archive.Application.Windows.Desktop_Capabilities :=
           Archive.Application.Windows.Runtime_Capabilities;
         Plan : constant Archive.Application.Windows.Live_Smoke_Plan :=
           Archive.Application.Windows.Default_Live_Smoke_Plan;
      begin
         Assert (Caps.Headless_Rendering, "desktop capabilities retain headless rendering path");
         Assert (Caps.Event_Loop_Model and then Caps.Resize_Runtime_Model and then Caps.Vulkan_Presentation,
                 "desktop capabilities expose live event, resize, and presentation models");
         Assert (Plan.Can_Run = Caps.Live_Window_Smoke_Ready,
                 "live smoke plan follows detected runtime capabilities");
         Assert (Plan.Width > 0 and then Plan.Height > 0,
                 "live smoke plan has bounded frame geometry");
         Assert (Plan.Frame_Count >= 2 and then Plan.Input_Poll_Count >= 2,
                 "live smoke plan exercises repeated event polling and rendering");
         Assert (Plan.Resize_Width > 0 and then Plan.Resize_Height > 0,
                 "live smoke plan includes a bounded resize step");
      end;

      declare
         Executable_Plan : Archive.Application.Windows.Live_Smoke_Plan :=
           Archive.Application.Windows.Default_Live_Smoke_Plan;
         Result          : Archive.Application.Windows.Live_Smoke_Result;
      begin
         Executable_Plan.Can_Run := True;
         Executable_Plan.Needs_Display := False;
         Executable_Plan.Needs_Vulkan := False;
         Executable_Plan.Frame_Count := 2;
         Executable_Plan.Input_Poll_Count := 2;
         Executable_Plan.Resize_Width := 640;
         Executable_Plan.Resize_Height := 480;
         Result := Archive.Application.Windows.Live_Smoke (Executable_Plan);
         if Result.Attempted and then Result.Window_Created then
            Assert (Result.Runtime_Validated,
                    "attempted live smoke validates runtime before rendering");
            Assert (Result.Frames_Attempted >= 1,
                    "attempted live smoke renders at least one frame");
            Assert (Result.Input_Polled,
                    "attempted live smoke polls desktop events");
         else
            Assert (To_String (Result.Error_Key) = "runtime.live.failed",
                    "unavailable native live smoke returns stable failure key");
         end if;
      end;

      declare
         Skipped_Plan : Archive.Application.Windows.Live_Smoke_Plan :=
           Archive.Application.Windows.Default_Live_Smoke_Plan;
         Result       : Archive.Application.Windows.Live_Smoke_Result;
      begin
         Skipped_Plan.Can_Run := False;
         Skipped_Plan.Reason_Key := To_Unbounded_String ("runtime.live.test_skip");
         Result := Archive.Application.Windows.Live_Smoke (Skipped_Plan);
         Assert (not Result.Attempted and then Result.Skipped_By_Plan,
                 "live smoke skip path does not open a native window");
         Assert (To_String (Result.Error_Key) = "runtime.live.test_skip",
                 "live smoke skip path retains stable reason key");
      end;

      declare
         Report : constant String := Archive.Application.Live_Smoke_Report;
      begin
         Assert (Ada.Strings.Fixed.Index (Report, "archive live runtime:") > 0,
                 "application exposes live runtime report");
         Assert (Ada.Strings.Fixed.Index (Report, "smoke_ready=") > 0,
                 "live runtime report includes smoke readiness");
         Assert (Ada.Strings.Fixed.Index (Report, "status=") > 0,
                 "live runtime report includes Vulkan status");
         Assert (Ada.Strings.Fixed.Index (Report, "resized=") > 0,
                 "live runtime report includes resize smoke state");
         Assert (Ada.Strings.Fixed.Index (Report, "runtime_validated=") > 0,
                 "live runtime report includes runtime validation state");
      end;
   end Test_Live_Runtime;

   procedure Test_Settings (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      Settings : Archive.Settings.Settings_Model := Archive.Settings.Default_Settings;
      OK       : Boolean := False;

      function Settings_Fixture_Path (Name : String) return String is
         Tests_Path : constant String := "fixtures/settings/" & Name;
         Root_Path  : constant String := "tests/fixtures/settings/" & Name;
      begin
         if Ada.Directories.Exists (Tests_Path) then
            return Tests_Path;
         end if;
         return Root_Path;
      end Settings_Fixture_Path;
   begin
      Assert (Settings.Preview_Visible, "preview visible by default");
      Assert
        (Archive.Settings.Clamp_Preview_Limit (Archive.Settings.Hard_Max_Preview_Bytes + 1)
         = Archive.Settings.Hard_Max_Preview_Bytes,
         "preview limit clamps to hard ceiling");
      Assert
        (Archive.Settings.View_Mode_Token (Archive.Types.Details_View) = "details",
         "view mode persists stable token");
      Assert
        (Archive.Settings.Parse_View_Mode ("compact", OK) = Archive.Types.Compact_View and then OK,
         "view mode token parses");
      Assert
        (Archive.Settings.Conflict_Policy_Token (Archive.Settings.Overwrite) = "overwrite",
         "conflict policy persists stable token");
      Assert
        (Archive.Settings.Parse_Conflict_Policy ("rename", OK) = Archive.Settings.Rename and then OK,
         "conflict policy token parses");
      Assert
        (Archive.Settings.Link_Policy_Token (Archive.Settings.Safe_Internal_Links) = "safe-internal",
         "link policy persists stable token");
      Assert
        (Archive.Settings.Parse_Link_Policy ("skip", OK) = Archive.Settings.Skip_Links and then OK,
         "link policy token parses");
      Assert
        (Natural (Settings.Details_Columns.Length) = 7,
         "settings default details columns come from registry");
      Assert
        (Settings.Details_Columns.Element (1) = Archive.View_Snapshots.Columns.Name_Column,
         "settings default columns use stable ids");
      Assert
        (Ada.Strings.Fixed.Index (Archive.Settings.Serialize (Settings), "schema=2") = 1,
         "settings serialize canonical current schema");

      declare
         Migrated : constant Archive.Settings.Settings_Parse_Result :=
           Archive.Settings.Parse
             ("schema=0" & ASCII.LF
              & "default_view=compact" & ASCII.LF
              & "preview_visible=false" & ASCII.LF);
      begin
         Assert (Migrated.Success, "schema zero settings migrate");
         Assert (Migrated.Settings.Default_View = Archive.Types.Compact_View,
                 "schema zero migration keeps stable view token");
         Assert (not Migrated.Settings.Preview_Visible,
                 "schema zero migration keeps preview visibility");
         Assert
           (Migrated.Settings.Conflict_Policy = Archive.Settings.Ask
            and then Migrated.Settings.Write_Conflict_Policy = Archive.Settings.Ask
            and then Migrated.Settings.Link_Policy = Archive.Settings.Skip_Links,
            "schema zero migration supplies new policy defaults");
         Assert
           (Ada.Strings.Fixed.Index
              (Archive.Settings.Serialize (Migrated.Settings), "schema=2") = 1,
            "migrated settings serialize as current schema");
      end;

      Settings.Default_View := Archive.Types.Details_View;
      Settings.Preview_Visible := False;
      Settings.Preview_Byte_Limit := 42;
      Settings.Per_Entry_Extraction_Limit := Archive.Resource_Limits.Limit_Value (123);
      Settings.Total_Extraction_Limit := Archive.Resource_Limits.Limit_Value (456);
      Settings.Conflict_Policy := Archive.Settings.Overwrite;
      Settings.Write_Conflict_Policy := Archive.Settings.Rename;
      Settings.Link_Policy := Archive.Settings.Safe_Internal_Links;
      Settings.Show_Unsafe_Entries := False;
      Settings.Startup_Reopen_Recent := True;
      Settings.Window_Maximized := True;
      Archive.Settings.Remember_Recent_Archive (Settings, "/tmp/old.zip");
      Archive.Settings.Remember_Recent_Archive (Settings, "/tmp/new.zip");
      Archive.Settings.Remember_Recent_Archive (Settings, "/tmp/old.zip");
      Settings.Details_Columns.Clear;
      Settings.Details_Columns.Append (Archive.View_Snapshots.Columns.Name_Column);
      Settings.Details_Columns.Append (Archive.View_Snapshots.Columns.Archive_Position_Column);
      declare
         Parsed : constant Archive.Settings.Settings_Parse_Result :=
           Archive.Settings.Parse (Archive.Settings.Serialize (Settings));
      begin
         Assert (Parsed.Success, "serialized settings parse");
         Assert (Parsed.Settings.Default_View = Archive.Types.Details_View, "default view round trips");
         Assert (not Parsed.Settings.Preview_Visible, "preview visibility round trips");
         Assert (Parsed.Settings.Preview_Byte_Limit = 42, "preview limit round trips");
         Assert
           (Parsed.Settings.Per_Entry_Extraction_Limit = Archive.Resource_Limits.Limit_Value (123)
            and then Parsed.Settings.Total_Extraction_Limit = Archive.Resource_Limits.Limit_Value (456),
            "extraction output limits round trip");
         Assert
           (Parsed.Settings.Conflict_Policy = Archive.Settings.Overwrite
            and then Parsed.Settings.Write_Conflict_Policy = Archive.Settings.Rename
            and then Parsed.Settings.Link_Policy = Archive.Settings.Safe_Internal_Links
            and then not Parsed.Settings.Show_Unsafe_Entries
            and then Parsed.Settings.Startup_Reopen_Recent
            and then Parsed.Settings.Window_Maximized,
            "write, extraction, startup, and window policies round trip as stable tokens");
         Assert
           (Natural (Parsed.Settings.Details_Columns.Length) = 2
            and then Parsed.Settings.Details_Columns.Element (2) =
              Archive.View_Snapshots.Columns.Archive_Position_Column,
            "details columns round trip as stable tokens");
         Assert
           (Natural (Parsed.Settings.Recent_Archives.Length) = 2
            and then To_String (Parsed.Settings.Recent_Archives.Element (1)) = "/tmp/old.zip"
            and then To_String (Parsed.Settings.Recent_Archives.Element (2)) = "/tmp/new.zip",
            "recent archives de-duplicate, promote, and round trip");
      end;

      declare
         Many : Archive.Settings.Settings_Model := Archive.Settings.Default_Settings;
      begin
         for Index in 1 .. Archive.Settings.Max_Recent_Items + 2 loop
            Archive.Settings.Remember_Recent_Archive
              (Many, "/tmp/recent-" & Natural'Image (Index) & ".zip");
         end loop;
         Assert
           (Natural (Many.Recent_Archives.Length) = Archive.Settings.Max_Recent_Items,
            "recent archives are bounded by settings max retention");
      end;

      declare
         Parsed : constant Archive.Settings.Settings_Parse_Result :=
           Archive.Settings.Parse
             ("schema=2" & ASCII.LF
              & "unknown_key=kept-for-future" & ASCII.LF
              & "preview_byte_limit="
              & Natural'Image (Archive.Settings.Hard_Max_Preview_Bytes + 99) & ASCII.LF);
      begin
         Assert (Parsed.Success, "unknown settings keys are tolerated");
         Assert
           (Parsed.Settings.Preview_Byte_Limit = Archive.Settings.Hard_Max_Preview_Bytes,
            "parsed preview limit clamps to hard ceiling");
      end;

      declare
         Parsed : constant Archive.Settings.Settings_Parse_Result :=
           Archive.Settings.Parse
             ("schema=2" & ASCII.LF
              & "per_entry_extraction_limit=0" & ASCII.LF
              & "total_extraction_limit="
              & Archive.Resource_Limits.Limit_Value'Image
                  (Archive.Resource_Limits.Hard_Ceiling
                     (Archive.Resource_Limits.Total_Extraction_Output) + 1) & ASCII.LF);
      begin
         Assert (Parsed.Success, "extraction limits recover through validation");
         Assert
           (Parsed.Settings.Per_Entry_Extraction_Limit =
              Archive.Resource_Limits.Default_Configured
                (Archive.Resource_Limits.Per_Entry_Extraction_Output),
            "zero per-entry extraction limit recovers to default");
         Assert
           (Parsed.Settings.Total_Extraction_Limit =
              Archive.Resource_Limits.Hard_Ceiling
                (Archive.Resource_Limits.Total_Extraction_Output),
            "oversized total extraction limit clamps to hard ceiling");
      end;

      declare
         Parsed : constant Archive.Settings.Settings_Parse_Result :=
           Archive.Settings.Parse ("schema=2" & ASCII.LF & "default_view=localized-name" & ASCII.LF);
      begin
         Assert (not Parsed.Success, "invalid stable token fails parse");
         Assert (To_String (Parsed.Error_Key) = "settings.invalid", "invalid settings has message id");
      end;

      declare
         Parsed : constant Archive.Settings.Settings_Parse_Result :=
           Archive.Settings.Parse
             ("schema=2" & ASCII.LF & "details_columns=name,localized-label" & ASCII.LF);
      begin
         Assert (not Parsed.Success, "invalid details column token fails parse");
         Assert
           (Natural (Parsed.Settings.Details_Columns.Length) = 1
            and then Parsed.Settings.Details_Columns.Element (1) =
              Archive.View_Snapshots.Columns.Name_Column,
            "valid parsed details columns are retained on token failure");
      end;

      declare
         Parsed : constant Archive.Settings.Settings_Parse_Result :=
           Archive.Settings.Parse
             ("schema=2" & ASCII.LF
              & "conflict_policy=localized-name" & ASCII.LF
              & "write_conflict_policy=rename" & ASCII.LF
              & "link_policy=safe-internal" & ASCII.LF);
      begin
         Assert (not Parsed.Success, "invalid conflict policy token fails parse");
         Assert
           (Parsed.Settings.Write_Conflict_Policy = Archive.Settings.Rename
            and then Parsed.Settings.Link_Policy = Archive.Settings.Safe_Internal_Links,
            "valid write and link policies survive neighboring token failure");
      end;

      declare
         Parsed : constant Archive.Settings.Settings_Parse_Result :=
           Archive.Settings.Parse
             ("schema=2" & ASCII.LF
              & "conflict_policy=skip" & ASCII.LF
              & "write_conflict_policy=localized-label" & ASCII.LF
              & "startup_reopen_recent=true" & ASCII.LF
              & "link_policy=localized-label" & ASCII.LF);
      begin
         Assert (not Parsed.Success, "invalid write/link policy token fails parse");
         Assert
           (Parsed.Settings.Conflict_Policy = Archive.Settings.Skip
            and then Parsed.Settings.Startup_Reopen_Recent,
            "valid conflict and startup policies survive neighboring token failure");
      end;

      declare
         Current : constant Archive.Settings.Settings_Parse_Result :=
           Archive.Settings.Load (Settings_Fixture_Path ("current-valid.settings"));
         Migrated : constant Archive.Settings.Settings_Parse_Result :=
           Archive.Settings.Load (Settings_Fixture_Path ("schema0-migration.settings"));
      begin
         Assert (Current.Success, "current settings fixture loads");
         Assert
           (Current.Settings.Default_View = Archive.Types.Details_View
            and then not Current.Settings.Directories_First
            and then not Current.Settings.Preview_Visible
            and then Current.Settings.Preview_Byte_Limit = 64,
            "current settings fixture retains view and preview fields");
         Assert
           (Current.Settings.Conflict_Policy = Archive.Settings.Rename
            and then Current.Settings.Write_Conflict_Policy = Archive.Settings.Overwrite
            and then Current.Settings.Link_Policy = Archive.Settings.Safe_Internal_Links
            and then not Current.Settings.Show_Unsafe_Entries
            and then Current.Settings.Startup_Reopen_Recent,
            "current settings fixture retains stable policy tokens");
         Assert
           (Natural (Current.Settings.Details_Columns.Length) = 2
            and then Current.Settings.Details_Columns.Element (2) =
              Archive.View_Snapshots.Columns.Path_Safety_Column,
            "current settings fixture uses stable details column ids");
         Assert
           (Natural (Current.Settings.Recent_Archives.Length) = 2
            and then To_String (Current.Settings.Recent_Archives.Element (1)) =
              "/archives/one.zip"
            and then To_String (Current.Settings.Recent_Archives.Element (2)) =
              "/archives/two.tar.gz",
            "current settings fixture deduplicates recent archives deterministically");

         Assert (Migrated.Success, "schema zero settings fixture migrates");
         Assert
           (Migrated.Settings.Default_View = Archive.Types.Compact_View
            and then not Migrated.Settings.Preview_Visible
            and then Migrated.Settings.Conflict_Policy = Archive.Settings.Ask
            and then Migrated.Settings.Write_Conflict_Policy = Archive.Settings.Ask
            and then Migrated.Settings.Link_Policy = Archive.Settings.Skip_Links,
            "schema zero fixture fills current conservative defaults");
         Assert
           (Ada.Strings.Fixed.Index
              (Archive.Settings.Serialize (Migrated.Settings), "schema=2") = 1,
            "schema zero fixture serializes to the current schema");
      end;

      declare
         Dir  : constant String := "obj/settings-io-test";
         Path : constant String := Dir & "/archive.settings";
         Invalid_Fixture : constant String :=
           Settings_Fixture_Path ("invalid-future-schema.settings");
         Invalid_Copy : constant String := Dir & "/invalid-future-schema.settings";
         Invalid_Quarantine : constant String :=
           Archive.Settings.Quarantine_Path (Invalid_Copy);
      begin
         if not Ada.Directories.Exists (Dir) then
            Ada.Directories.Create_Path (Dir);
         end if;
         Settings := Archive.Settings.Default_Settings;
         Settings.Default_View := Archive.Types.Compact_View;
         Settings.Preview_Visible := False;
         Settings.Conflict_Policy := Archive.Settings.Rename;
         Settings.Write_Conflict_Policy := Archive.Settings.Overwrite;
         Settings.Link_Policy := Archive.Settings.Safe_Internal_Links;
         Settings.Show_Unsafe_Entries := False;
         Settings.Startup_Reopen_Recent := True;
         Settings.Window_Maximized := True;
         Settings.Details_Columns.Clear;
         Settings.Details_Columns.Append (Archive.View_Snapshots.Columns.Name_Column);
         Settings.Details_Columns.Append (Archive.View_Snapshots.Columns.Path_Safety_Column);
         Archive.Settings.Remember_Recent_Archive (Settings, Dir & "/one.zip");
         Archive.Settings.Remember_Recent_Archive (Settings, Dir & "/two.zip");

         declare
            Saved : constant Archive.Settings.Settings_Write_Result :=
              Archive.Settings.Save (Path, Settings);
            Loaded : Archive.Settings.Settings_Parse_Result;
         begin
            Assert (Saved.Success, "settings save succeeds");
            Loaded := Archive.Settings.Load (Path);
            Assert (Loaded.Success, "settings load succeeds");
            Assert (Loaded.Settings.Default_View = Archive.Types.Compact_View, "loaded view mode matches");
            Assert (not Loaded.Settings.Preview_Visible, "loaded preview visibility matches");
            Assert
              (Loaded.Settings.Conflict_Policy = Archive.Settings.Rename
               and then Loaded.Settings.Write_Conflict_Policy = Archive.Settings.Overwrite
               and then Loaded.Settings.Link_Policy = Archive.Settings.Safe_Internal_Links
               and then not Loaded.Settings.Show_Unsafe_Entries
               and then Loaded.Settings.Startup_Reopen_Recent
               and then Loaded.Settings.Window_Maximized,
               "loaded settings retain write, extraction, startup, window, and link policies");
            Assert
              (Loaded.Settings.Details_Columns.Element (2) =
                 Archive.View_Snapshots.Columns.Path_Safety_Column,
               "loaded details columns match persisted stable token");
            Assert
              (Natural (Loaded.Settings.Recent_Archives.Length) = 2
               and then To_String (Loaded.Settings.Recent_Archives.Element (1)) = (Dir & "/two.zip"),
               "loaded settings retain recent archive list");
         end;

         Write_Bytes
           (Path,
            [1 => Zlib.Byte (Character'Pos ('s')),
             2 => Zlib.Byte (Character'Pos ('c')),
             3 => Zlib.Byte (Character'Pos ('h')),
             4 => Zlib.Byte (Character'Pos ('e')),
             5 => Zlib.Byte (Character'Pos ('m')),
             6 => Zlib.Byte (Character'Pos ('a')),
             7 => Zlib.Byte (Character'Pos ('=')),
             8 => Zlib.Byte (Character'Pos ('9'))]);
         declare
            Loaded : constant Archive.Settings.Settings_Parse_Result :=
              Archive.Settings.Load (Path);
         begin
            Assert (not Loaded.Success, "invalid settings load fails");
            Assert (To_String (Loaded.Error_Key) = "settings.invalid", "invalid load reports stable key");
            Assert
              (Loaded.Settings.Default_View = Archive.Types.Grid_View,
               "invalid load falls back to defaults");
            Assert
              ((not Ada.Directories.Exists (Path))
               and then Ada.Directories.Exists (Archive.Settings.Quarantine_Path (Path)),
               "invalid settings load quarantines original file");
         end;

         if Ada.Directories.Exists (Invalid_Copy) then
            Ada.Directories.Delete_File (Invalid_Copy);
         end if;
         if Ada.Directories.Exists (Invalid_Quarantine) then
            Ada.Directories.Delete_File (Invalid_Quarantine);
         end if;
         Write_Bytes (Invalid_Copy, Read_All_Bytes (Invalid_Fixture));
         declare
            Loaded : constant Archive.Settings.Settings_Parse_Result :=
              Archive.Settings.Load (Invalid_Copy);
         begin
            Assert (not Loaded.Success, "invalid settings fixture fails load");
            Assert
              (To_String (Loaded.Error_Key) = "settings.invalid",
               "invalid settings fixture reports stable recovery key");
            Assert
              (Loaded.Settings.Default_View = Archive.Types.Grid_View
               and then Loaded.Settings.Preview_Visible,
               "invalid settings fixture recovers to compiled defaults");
            Assert
              ((not Ada.Directories.Exists (Invalid_Copy))
               and then Ada.Directories.Exists (Invalid_Quarantine),
               "invalid settings fixture is quarantined during load");
            Assert
              (CRC32_Compute (Read_All_Bytes (Invalid_Quarantine)) =
                 CRC32_Compute (Read_All_Bytes (Invalid_Fixture)),
               "settings quarantine preserves the invalid input bytes");
         end;
      end;
   end Test_Settings;

   procedure Test_Resource_Limits (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      use Archive.Resource_Limits;
      Default_Preview : constant Limit_Value := Default_Configured (Preview_Input_Bytes);
      Ceiling_Preview : constant Limit_Value := Hard_Ceiling (Preview_Input_Bytes);
      OK              : constant Validation_Result :=
        Validate (Preview_Input_Bytes, Default_Preview);
      Clamped         : constant Validation_Result :=
        Validate (Preview_Input_Bytes, Ceiling_Preview + 1);
      Rejected        : constant Validation_Result :=
        Validate (Preview_Input_Bytes, Ceiling_Preview + 1, Clamp_To_Hard => False);
      Zero            : constant Validation_Result :=
        Validate (Event_Queue_Capacity, 0);
   begin
      Assert (Default_Preview < Ceiling_Preview, "configured default is below hard ceiling");
      Assert (OK.Status = Accepted, "default preview limit is accepted");
      Assert (OK.Effective = Default_Preview, "accepted limit remains unchanged");
      Assert
        (Clamped.Status = Clamped_To_Hard_Ceiling
         and then Clamped.Effective = Ceiling_Preview,
         "configured limit can clamp to hard ceiling");
      Assert
        (Rejected.Status = Rejected_Above_Hard_Ceiling
         and then Rejected.Effective = Default_Preview,
         "non-clamping validation rejects hard-ceiling violations");
      Assert
        (Zero.Status = Rejected_Zero
         and then Zero.Effective = Default_Configured (Event_Queue_Capacity),
         "zero is rejected unless explicitly allowed");
      Assert
        (Validate (Event_Queue_Capacity, 0, Zero_Is_Allowed => True).Status = Accepted,
         "zero can be allowed for domains that support it");
   end Test_Resource_Limits;

   procedure Test_Localization (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
   begin
      Assert (Archive.Localization.Normalize_Locale ("C") = "en", "C locale maps to English fallback");
      Assert (Archive.Localization.Normalize_Locale ("de_DE.UTF-8") = "de-DE", "locale normalization");
      Assert (Archive.Localization.Text ("format.zip.name") = "ZIP", "format key resolves");
      Assert
        (Archive.Localization.Text ("unavailable.unsafe_path") /=
           "unavailable.unsafe_path",
         "unavailable reason key resolves");
      Assert
        (Archive.Localization.Text ("missing.key") = "missing.key",
         "missing key falls back to stable message id");
   end Test_Localization;

   function Suite return AUnit.Test_Suites.Access_Test_Suite is
      Result : constant AUnit.Test_Suites.Access_Test_Suite := AUnit.Test_Suites.New_Suite;
   begin
      pragma Warnings (Off, "*anonymous access type allocator*");
      Result.Add_Test (new Core_Test_Case);
      pragma Warnings (On, "*anonymous access type allocator*");
      return Result;
   end Suite;
end Archive_Suite.Core;
