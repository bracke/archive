with Archive.Archives.Errors;
with Archive.Writes.Plans;
with Tarlib.Outputs;

package Archive.Writes.Tar is
   function Build_Stream
     (Plan : Archive.Writes.Plans.Write_Plan;
      Sink : in out Tarlib.Outputs.Output_Sink'Class)
      return Archive.Archives.Errors.Error_Code;

   function Build_Stream
     (Plan        : Archive.Writes.Plans.Write_Plan;
      Sink        : in out Tarlib.Outputs.Output_Sink'Class;
      Source_Path : String)
      return Archive.Archives.Errors.Error_Code;
end Archive.Writes.Tar;
