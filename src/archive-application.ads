with Archive.Model;
with Archive.Types;

package Archive.Application is
   subtype UString is Archive.Types.UString;
   package String_Vectors renames Archive.Types.String_Vectors;

   type Run_Mode is
     (Desktop_Run,
      Live_Smoke_Run,
      Headless_GUI_Run,
      Headless_Smoke_Run,
      Version_Run,
      Help_Run);

   type Run_Configuration is record
      Mode  : Run_Mode := Desktop_Run;
      Paths : String_Vectors.Vector;
   end record;

   function Parse_Run_Configuration (Arguments : String_Vectors.Vector) return Run_Configuration;
   function Help_Text (Locale : String := "en") return String;
   function Version_Text return String;
   function Runtime_Smoke_Report (Locale : String := "en") return String;
   function Headless_GUI_Report
     (Locale       : String := "en";
      Initial_Path : String := "") return String;
   function Live_Smoke_Report return String;
   function Desktop_Shell_Report
     (Locale       : String := "en";
      Initial_Path : String := "") return String;
   procedure Run;
end Archive.Application;
