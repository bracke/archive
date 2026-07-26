with Archive.Archives.Errors;
with Archive.Writes.Plans;
with Ada.Streams;

package Archive.Writes.Zip is
   type Output_Sink is limited interface;

   procedure Write
     (Sink   : in out Output_Sink;
      Data   : Ada.Streams.Stream_Element_Array;
      Status : out Archive.Archives.Errors.Error_Code) is abstract;

   function Build_Stored_Stream
     (Plan : Archive.Writes.Plans.Write_Plan;
      Sink : in out Output_Sink'Class)
      return Archive.Archives.Errors.Error_Code;

   function Build_Stored_Stream
     (Plan        : Archive.Writes.Plans.Write_Plan;
      Sink        : in out Output_Sink'Class;
      Source_Path : String;
      Source_Name : String := "")
      return Archive.Archives.Errors.Error_Code;

   function Build_Deflate_Stream
     (Plan : Archive.Writes.Plans.Write_Plan;
      Sink : in out Output_Sink'Class)
      return Archive.Archives.Errors.Error_Code;

   function Build_Deflate_Stream
     (Plan        : Archive.Writes.Plans.Write_Plan;
      Sink        : in out Output_Sink'Class;
      Source_Path : String;
      Source_Name : String := "")
      return Archive.Archives.Errors.Error_Code;

   function Build_External_Stream
     (Plan        : Archive.Writes.Plans.Write_Plan;
      Sink        : in out Output_Sink'Class;
      Method_Name : String)
      return Archive.Archives.Errors.Error_Code;
end Archive.Writes.Zip;
