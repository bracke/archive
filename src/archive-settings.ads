with Archive.Types;
with Archive.Resource_Limits;
with Archive.View_Snapshots.Columns;

package Archive.Settings is
   subtype UString is Archive.Types.UString;

   Max_Recent_Items : constant := 50;
   Current_Schema : constant Natural := 2;
   Hard_Max_Preview_Bytes : constant Natural :=
     Natural
       (Archive.Resource_Limits.Hard_Ceiling
          (Archive.Resource_Limits.Preview_Input_Bytes));

   type Extraction_Conflict_Policy is (Ask, Skip, Overwrite, Rename);
   type Link_Extraction_Policy is (Skip_Links, Safe_Internal_Links);

   type Settings_Model is record
      Locale_Mode            : UString;
      Explicit_Locale        : UString;
      Default_View           : Archive.Types.View_Mode := Archive.Types.Grid_View;
      Details_Columns        : Archive.View_Snapshots.Columns.Column_Vectors.Vector;
      Directories_First      : Boolean := True;
      Preview_Visible        : Boolean := True;
      Preview_Byte_Limit     : Natural :=
        Natural
          (Archive.Resource_Limits.Default_Configured
             (Archive.Resource_Limits.Preview_Input_Bytes));
      Per_Entry_Extraction_Limit : Archive.Resource_Limits.Limit_Value :=
        Archive.Resource_Limits.Default_Configured
          (Archive.Resource_Limits.Per_Entry_Extraction_Output);
      Total_Extraction_Limit : Archive.Resource_Limits.Limit_Value :=
        Archive.Resource_Limits.Default_Configured
          (Archive.Resource_Limits.Total_Extraction_Output);
      Conflict_Policy        : Extraction_Conflict_Policy := Ask;
      Write_Conflict_Policy  : Extraction_Conflict_Policy := Ask;
      Link_Policy            : Link_Extraction_Policy := Skip_Links;
      Show_Unsafe_Entries    : Boolean := True;
      Startup_Reopen_Recent  : Boolean := False;
      Recent_Archives        : Archive.Types.String_Vectors.Vector;
      Window_Width           : Natural := 0;
      Window_Height          : Natural := 0;
      Window_Maximized       : Boolean := False;
      Toolbar_Visible        : Boolean := True;
      Status_Bar_Visible     : Boolean := True;
   end record;

   type Settings_Parse_Result is record
      Success   : Boolean := True;
      Settings  : Settings_Model;
      Error_Key : UString;
   end record;

   type Settings_Write_Result is record
      Success   : Boolean := True;
      Error_Key : UString;
   end record;

   function Default_Settings return Settings_Model;
   function Clamp_Preview_Limit (Value : Natural) return Natural;
   function Validate_Extraction_Limit
     (Id    : Archive.Resource_Limits.Limit_Id;
      Value : Archive.Resource_Limits.Limit_Value)
      return Archive.Resource_Limits.Limit_Value;
   function View_Mode_Token (Mode : Archive.Types.View_Mode) return String;
   function Parse_View_Mode (Token : String; Success : out Boolean) return Archive.Types.View_Mode;
   function Conflict_Policy_Token (Policy : Extraction_Conflict_Policy) return String;
   function Parse_Conflict_Policy
     (Token   : String;
      Success : out Boolean)
      return Extraction_Conflict_Policy;
   function Link_Policy_Token (Policy : Link_Extraction_Policy) return String;
   function Parse_Link_Policy
     (Token   : String;
      Success : out Boolean)
      return Link_Extraction_Policy;
   procedure Remember_Recent_Archive
     (Settings : in out Settings_Model;
      Path     : String);
   function Serialize (Settings : Settings_Model) return String;
   function Parse (Text : String) return Settings_Parse_Result;
   function Quarantine_Path (Path : String) return String;
   function Load (Path : String) return Settings_Parse_Result;
   function Save (Path : String; Settings : Settings_Model) return Settings_Write_Result;
end Archive.Settings;
