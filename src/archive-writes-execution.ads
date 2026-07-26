with Archive.Writes.Plans;
with Archive.Writes.Results;
with Archive.Archives.Errors;
with Archive.Archives.Formats;

package Archive.Writes.Execution is
   function Stage_Gzip_As_Tar
     (Source_Path : String;
      Target_Path : String)
      return Archive.Archives.Errors.Error_Code;

   function Publish_Archive_From_File
     (Destination_Path    : String;
      Plan                : Archive.Writes.Plans.Write_Plan;
      Payload_Source_Path : String;
      Overwrite           : Boolean := False;
      Expected_Format     : Archive.Archives.Formats.Format_Id :=
        Archive.Archives.Formats.Unknown_Format;
      Source_Name         : String := "";
      Cancelled           : Boolean := False)
      return Archive.Writes.Results.Publish_Result;

   function Publish_Zip_Stored
     (Destination_Path : String;
      Plan             : Archive.Writes.Plans.Write_Plan;
      Overwrite        : Boolean := False;
      Cancelled        : Boolean := False)
      return Archive.Writes.Results.Publish_Result;

   function Publish_Zip_Stored
     (Destination_Path : String;
      Plan             : Archive.Writes.Plans.Write_Plan;
      Source_Path      : String;
      Source_Name      : String := "";
      Overwrite        : Boolean := False;
      Cancelled        : Boolean := False)
      return Archive.Writes.Results.Publish_Result;

   function Publish_Zip_Deflate
     (Destination_Path : String;
      Plan             : Archive.Writes.Plans.Write_Plan;
      Overwrite        : Boolean := False;
      Cancelled        : Boolean := False)
      return Archive.Writes.Results.Publish_Result;

   function Publish_Zip_Deflate
     (Destination_Path : String;
      Plan             : Archive.Writes.Plans.Write_Plan;
      Source_Path      : String;
      Source_Name      : String := "";
      Overwrite        : Boolean := False;
      Cancelled        : Boolean := False)
      return Archive.Writes.Results.Publish_Result;

   function Publish_Tar
     (Destination_Path : String;
      Plan             : Archive.Writes.Plans.Write_Plan;
      Overwrite        : Boolean := False;
      Cancelled        : Boolean := False)
      return Archive.Writes.Results.Publish_Result;

   function Publish_Tar
     (Destination_Path : String;
      Plan             : Archive.Writes.Plans.Write_Plan;
      Source_Path      : String;
      Overwrite        : Boolean := False;
      Cancelled        : Boolean := False)
      return Archive.Writes.Results.Publish_Result;

   function Publish_Tar_Gzip
     (Destination_Path : String;
      Plan             : Archive.Writes.Plans.Write_Plan;
      Overwrite        : Boolean := False;
      Cancelled        : Boolean := False)
      return Archive.Writes.Results.Publish_Result;

   function Publish_Tar_Gzip
     (Destination_Path : String;
      Plan             : Archive.Writes.Plans.Write_Plan;
      Source_Path      : String;
      Overwrite        : Boolean := False;
      Cancelled        : Boolean := False)
      return Archive.Writes.Results.Publish_Result;

   function Publish_Gzip
     (Destination_Path : String;
      Plan             : Archive.Writes.Plans.Write_Plan;
      Overwrite        : Boolean := False;
      Cancelled        : Boolean := False)
      return Archive.Writes.Results.Publish_Result;
end Archive.Writes.Execution;
