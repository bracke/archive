with Ada.Command_Line;
with Ada.Strings.Unbounded;
with Ada.Text_IO;

with Archive.Localization;
with Archive.Application.Windows;
with Archive.GUI_Runtime;
with Archive.Operations.Opening;

package body Archive.Application is
   use Ada.Strings.Unbounded;

   function Parse_Run_Configuration (Arguments : String_Vectors.Vector) return Run_Configuration is
      Result : Run_Configuration;
   begin
      for Arg of Arguments loop
         declare
            Text : constant String := To_String (Arg);
         begin
            if Text = "--help" or else Text = "-h" then
               Result.Mode := Help_Run;
            elsif Text = "--version" then
               Result.Mode := Version_Run;
            elsif Text = "--headless-smoke" then
               Result.Mode := Headless_Smoke_Run;
            elsif Text = "--headless-gui" then
               Result.Mode := Headless_GUI_Run;
            elsif Text = "--live-smoke" then
               Result.Mode := Live_Smoke_Run;
            else
               Result.Paths.Append (Arg);
            end if;
         end;
      end loop;
      return Result;
   end Parse_Run_Configuration;

   function Help_Text (Locale : String := "en") return String is
   begin
      return Archive.Localization.Text ("help.summary", Locale) & ASCII.LF
        & "Usage: archive [--help] [--version] [--headless-smoke] [--headless-gui] [--live-smoke] [ARCHIVE...]";
   end Help_Text;

   function Version_Text return String is
   begin
      return Archive.Localization.Text ("application.version", "en");
   end Version_Text;

   function Runtime_Smoke_Report (Locale : String := "en") return String is
      pragma Unreferenced (Locale);
      Model : Archive.Model.Application_Model;
   begin
      Archive.Model.Initialize (Model);
      return "archive smoke: no archive state ready";
   end Runtime_Smoke_Report;

   procedure Start_Initial_Open
     (Runtime      : in out Archive.GUI_Runtime.Runtime_State;
      Initial_Path : String)
   is
   begin
      if Initial_Path /= "" then
         Archive.GUI_Runtime.Start_Open_Archive (Runtime, Initial_Path);
         for Attempt in 1 .. 10_000 loop
            declare
               Drain : constant Archive.Operations.Opening.Drain_Result :=
                 Archive.GUI_Runtime.Drain_Operations (Runtime);
            begin
               exit when Drain.Event_Seen;
            end;
         end loop;
      end if;
   end Start_Initial_Open;

   function First_Path_Or_Empty (Config : Run_Configuration) return String is
   begin
      if Config.Paths.Is_Empty then
         return "";
      else
         return To_String (Config.Paths.First_Element);
      end if;
   end First_Path_Or_Empty;

   function Headless_GUI_Report
     (Locale       : String := "en";
      Initial_Path : String := "") return String
   is
      Runtime : Archive.GUI_Runtime.Runtime_State;
   begin
      Archive.GUI_Runtime.Initialize (Runtime, Locale => Locale);
      Start_Initial_Open (Runtime, Initial_Path);
      return Archive.GUI_Runtime.Runtime_Report (Runtime);
   end Headless_GUI_Report;

   function Live_Smoke_Report return String is
   begin
      return Archive.Application.Windows.Live_Smoke_Report;
   end Live_Smoke_Report;

   function Desktop_Shell_Report
     (Locale       : String := "en";
      Initial_Path : String := "") return String
   is
      Runtime : Archive.GUI_Runtime.Runtime_State;
   begin
      Archive.GUI_Runtime.Initialize (Runtime, Locale => Locale);
      Start_Initial_Open (Runtime, Initial_Path);
      return Archive.GUI_Runtime.Runtime_Report (Runtime);
   end Desktop_Shell_Report;

   procedure Run is
      Args : String_Vectors.Vector;
   begin
      for Index in 1 .. Ada.Command_Line.Argument_Count loop
         Args.Append (To_Unbounded_String (Ada.Command_Line.Argument (Index)));
      end loop;

      declare
         Config : constant Run_Configuration := Parse_Run_Configuration (Args);
      begin
         case Config.Mode is
            when Help_Run =>
               Ada.Text_IO.Put_Line (Help_Text);
            when Version_Run =>
               Ada.Text_IO.Put_Line (Version_Text);
            when Headless_GUI_Run =>
               Ada.Text_IO.Put_Line
                 (Headless_GUI_Report (Initial_Path => First_Path_Or_Empty (Config)));
            when Live_Smoke_Run =>
               Ada.Text_IO.Put_Line (Live_Smoke_Report);
            when Headless_Smoke_Run =>
               Ada.Text_IO.Put_Line (Runtime_Smoke_Report);
            when Desktop_Run =>
               Archive.Application.Windows.Run (Initial_Path => First_Path_Or_Empty (Config));
         end case;
      end;
   end Run;
end Archive.Application;
