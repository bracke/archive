with Ada.Strings.Unbounded;

with Guikit.Layout;
with Guikit.List_Panel;
with Guikit.Widgets;

with Archive.Archives.Entries;
with Archive.Model;
with Archive.Settings;
with Archive.View_Snapshots.Command_Surfaces;

package body Archive.GUI_Frame is
   use Ada.Strings.Unbounded;

   Toolbar_Button_Padding : constant Natural := 8;

   Toolbar_Start : constant Natural := 260;
   Toolbar_Gap   : constant Natural := 4;

   function Button_Width (Label : Archive.Types.UString) return Natural is
     (Guikit.Layout.Label_Pixel_Width
        (To_String (Label), Guikit.Layout.Caret_Advance_Width (Archive.UI.Default_Line_Height))
      + 2 * Toolbar_Button_Padding);

   --  How many of the toolbar's commands are shown as buttons.
   function Shown_Commands
     (Shell : Archive.UI.Shell_Snapshot;
      Width : Natural)
      return Natural
   is
      Count  : constant Natural := Natural (Shell.Toolbar.Commands.Length);
      More_W : constant Natural := Button_Width (Shell.Toolbar_More_Label);
      X      : Natural := Toolbar_Start;
      Fits   : Natural := 0;
   begin
      for Command of Shell.Toolbar.Commands loop
         exit when X + Button_Width (Command.Name) > Width;
         X := X + Button_Width (Command.Name) + Toolbar_Gap;
         Fits := Fits + 1;
      end loop;
      if Fits = Count then
         return Count;
      end if;
      --  Make room for More after the last button shown.
      while Fits > 0 loop
         X := Toolbar_Start;
         for Index in 1 .. Fits loop
            X := X + Button_Width (Shell.Toolbar.Commands.Element (Index).Name) + Toolbar_Gap;
         end loop;
         exit when X + More_W <= Width;
         Fits := Fits - 1;
      end loop;
      return Fits;
   end Shown_Commands;

   function Toolbar_Buttons
     (Shell : Archive.UI.Shell_Snapshot;
      Width : Natural)
      return Toolbar_Button_Vectors.Vector
   is
      Shown  : constant Natural := Shown_Commands (Shell, Width);
      Result : Toolbar_Button_Vectors.Vector;
      X      : Natural := Toolbar_Start;
   begin
      --  Each button is as wide as its label, measured with the advance the
      --  renderer draws at.
      for Index in 1 .. Shown loop
         declare
            Command  : constant Archive.View_Snapshots.Command_Surfaces.Surface_Command :=
              Shell.Toolbar.Commands.Element (Index);
            Button_W : constant Natural := Button_Width (Command.Name);
         begin
            Result.Append
              (Toolbar_Button'(X => X, Y => 8, Width => Button_W, Height => 28,
                               Command => Command.Id, Enabled => Command.Enabled, Label => Command.Name,
                               More => False));
            X := X + Button_W + Toolbar_Gap;
         end;
      end loop;
      if Shown < Natural (Shell.Toolbar.Commands.Length) then
         Result.Append
           (Toolbar_Button'(X => X, Y => 8, Width => Button_Width (Shell.Toolbar_More_Label), Height => 28,
                            Command => Archive.Commands.No_Command, Enabled => True,
                            Label => Shell.Toolbar_More_Label, More => True));
      end if;
      return Result;
   end Toolbar_Buttons;

   function Toolbar_Overflow_Rows
     (Shell : Archive.UI.Shell_Snapshot;
      Width : Natural)
      return Toolbar_Button_Vectors.Vector
   is
      Shown   : constant Natural := Shown_Commands (Shell, Width);
      Buttons : constant Toolbar_Button_Vectors.Vector := Toolbar_Buttons (Shell, Width);
      Result  : Toolbar_Button_Vectors.Vector;
      Menu_W  : Natural := 0;
      Row_H   : constant Natural := Archive.UI.Default_Line_Height + 8;
   begin
      if Buttons.Is_Empty or else not Buttons.Last_Element.More then
         return Result;
      end if;
      for Index in Shown + 1 .. Natural (Shell.Toolbar.Commands.Length) loop
         Menu_W := Natural'Max (Menu_W, Button_Width (Shell.Toolbar.Commands.Element (Index).Name));
      end loop;
      declare
         More   : constant Toolbar_Button := Buttons.Last_Element;
         --  Under the More button, kept inside the window.
         Left   : constant Natural :=
           (if More.X + Menu_W > Width and then Width > Menu_W then Width - Menu_W else More.X);
         Y      : Natural := More.Y + More.Height + 2;
      begin
         for Index in Shown + 1 .. Natural (Shell.Toolbar.Commands.Length) loop
            declare
               Command : constant Archive.View_Snapshots.Command_Surfaces.Surface_Command :=
                 Shell.Toolbar.Commands.Element (Index);
            begin
               Result.Append
                 (Toolbar_Button'(X => Left, Y => Y, Width => Menu_W, Height => Row_H,
                                  Command => Command.Id, Enabled => Command.Enabled, Label => Command.Name,
                                  More => False));
               Y := Y + Row_H;
            end;
         end loop;
      end;
      return Result;
   end Toolbar_Overflow_Rows;
   use type Archive.Archives.Entries.Entry_Kind;
   use type Archive.Model.Focus_Region;
   use type Archive.Model.Overlay_Kind;
   use type Guikit.Item_Grid.View_Kind;

   procedure Add_Text
     (Commands : in out Guikit.Draw.Text_Command_Vectors.Vector;
      X        : Natural;
      Y        : Natural;
      Width    : Natural;
      Height   : Natural;
      Value    : Archive.Types.UString;
      Color    : Guikit.Draw.Render_Color := Guikit.Draw.Text_Color)
   is
   begin
      if Width > 0 and then Height > 0 and then Length (Value) > 0 then
         Commands.Append
           (Guikit.Draw.Text_Command'
              (X            => X,
               Y            => Y,
               Width        => Width,
               Height       => Height,
               Text         => Value,
               Color        => Color,
               Truncated    => False,
               Scale_To_Box => False,
               Italic       => False));
      end if;
   end Add_Text;

   procedure Add_Accessibility
     (Nodes       : in out Guikit.Draw.Accessibility_Node_Vectors.Vector;
      Role        : Guikit.Draw.Accessibility_Role;
      X           : Natural;
      Y           : Natural;
      Width       : Natural;
      Height      : Natural;
      Name        : Archive.Types.UString;
      Description : Archive.Types.UString := Null_Unbounded_String;
      Focused     : Boolean := False;
      Selected    : Boolean := False)
   is
   begin
      Nodes.Append
        (Guikit.Draw.Accessibility_Node'
           (Role        => Role,
            X           => X,
            Y           => Y,
            Width       => Width,
            Height      => Height,
            Name        => Name,
            Description => Description,
            Enabled     => True,
            Selected    => Selected,
            Focused     => Focused));
   end Add_Accessibility;

   function Grid_View (Mode : Archive.Types.View_Mode) return Guikit.Item_Grid.View_Kind is
   begin
      case Mode is
         when Archive.Types.Grid_View => return Guikit.Item_Grid.Icons_Large;
         when Archive.Types.Compact_View => return Guikit.Item_Grid.Icons_Small;
         when Archive.Types.Details_View => return Guikit.Item_Grid.Details;
      end case;
   end Grid_View;

   function Detail_Columns (X : Natural; W : Natural) return Guikit.Item_Grid.Detail_Column_Bounds is
      Result : Guikit.Item_Grid.Detail_Column_Bounds := [others => (X => 0, Width => 0)];
      Name_W : constant Natural := (if W > 360 then W / 3 else W / 2);
      Size_W : constant Natural := 96;
      Type_W : constant Natural := 140;
      Rest_X : constant Natural := X + Name_W;
   begin
      Result (Guikit.Item_Grid.Name_Column) := (X => X, Width => Name_W);
      if W > Name_W + Size_W then
         Result (Guikit.Item_Grid.Size_Column) := (X => Rest_X, Width => Size_W);
      end if;
      if W > Name_W + Size_W + Type_W then
         Result (Guikit.Item_Grid.Filetype_Column) := (X => Rest_X + Size_W, Width => Type_W);
      end if;
      return Result;
   end Detail_Columns;

   procedure Draw_Breadcrumb (Result : in out Frame; Shell : Archive.UI.Shell_Snapshot; W : Natural; H : Natural) is
      pragma Unreferenced (H);
      X : Natural := 12;
   begin
      if Shell.Breadcrumb.Valid and then not Shell.Breadcrumb.Items.Is_Empty then
         for Item of Shell.Breadcrumb.Items loop
            Add_Text (Result.Text, X, Shell.Layout.Breadcrumb_Y + 4, 140, 20, Item.Name,
                      Guikit.Draw.Text_Color);
            Add_Accessibility
              (Result.Accessibility, Guikit.Draw.Role_Button, X, Shell.Layout.Breadcrumb_Y,
               140, Shell.Layout.Breadcrumb_H, Item.Name);
            X := X + 148;
            exit when X + 80 >= W;
         end loop;
      else
         Add_Text (Result.Text, 12, Shell.Layout.Breadcrumb_Y + 4, W - 24, 20,
                   Shell.Breadcrumb_Label, Guikit.Draw.Muted_Text_Color);
      end if;
   end Draw_Breadcrumb;

   function Content_Cells (Shell : Archive.UI.Shell_Snapshot) return Guikit.Item_Grid.Item_Layout_Vectors.Vector is
      Items   : Guikit.Item_Grid.Layout_Item_Vectors.Vector;
      View    : constant Guikit.Item_Grid.View_Kind := Grid_View (Shell.Content_View.Mode);
      Header_H : constant Natural := 32;
      Content_Y : constant Natural := Shell.Layout.Content_Y + Header_H;
      Content_H : constant Natural :=
        (if Shell.Layout.Content_H > Header_H then Shell.Layout.Content_H - Header_H else 0);
   begin
      for I in 1 .. Natural (Shell.Content_Rows.Length) loop
         Items.Append
           (Guikit.Item_Grid.Layout_Item'
              (Visible_Index => I,
               Group_Header  => False,
               Label         => Shell.Content_Rows.Element (I).Name));
      end loop;

      return Guikit.Item_Grid.Calculate_Layout
        (Items         => Items,
         View          => View,
         Content_X     => 8,
         Content_Y     => Content_Y,
         Content_W     => (if Shell.Layout.Content_W > 16 then Shell.Layout.Content_W - 16 else 0),
         Content_H     => Content_H,
         Columns       => Detail_Columns (16, (if Shell.Layout.Content_W > 32 then Shell.Layout.Content_W - 32 else 0)),
         Scroll_Pixels => 0,
         Line_Height   => Archive.UI.Default_Line_Height);
   end Content_Cells;

   procedure Draw_Content (Result : in out Frame; Shell : Archive.UI.Shell_Snapshot; W : Natural; H : Natural) is
      pragma Unreferenced (W);
      Layouts : constant Guikit.Item_Grid.Item_Layout_Vectors.Vector := Content_Cells (Shell);
      View    : constant Guikit.Item_Grid.View_Kind := Grid_View (Shell.Content_View.Mode);
      Tips    : Guikit.Draw.Tooltip_Command_Vectors.Vector;
   begin
      for Cell of Layouts loop
         if Cell.Height > 0 and then Cell.Visible_Index > 0 then
            declare
               Row : constant Archive.UI.Content_Row_Snapshot :=
                 Shell.Content_Rows.Element (Cell.Visible_Index);
               Background : constant Guikit.Item_Grid.Background_Kind :=
                 (if Row.Selected then Guikit.Item_Grid.Selected
                  elsif Row.Focused then Guikit.Item_Grid.Hovered
                  elsif Cell.Visible_Index mod 2 = 0 then Guikit.Item_Grid.Alternate
                  else Guikit.Item_Grid.No_Background);
            begin
               Guikit.Item_Grid.Draw_Item_Background
                 (Result.Rectangles, Shell.Layout.Content_W, H, Cell, Background,
                  Guikit.Draw.Selection_Color, Guikit.Draw.Hover_Color,
                  Guikit.Draw.Border_Color, Guikit.Draw.Pane_Color);
               if Cell.Icon_Size > 0 then
                  Result.Rectangles.Append
                    (Guikit.Draw.Rectangle_Command'
                       (X => Cell.Icon_X, Y => Cell.Icon_Y, Width => Cell.Icon_Size,
                        Height => Cell.Icon_Size,
                        Color => (if Row.Kind = Archive.Archives.Entries.Directory
                                  then Guikit.Draw.Selection_Color
                                  else Guikit.Draw.Input_Color)));
               end if;
               Guikit.Item_Grid.Draw_Name_Field
                 (Result.Rectangles, Result.Text, Shell.Layout.Content_W, H, Cell, View,
                  False, Row.Focused, Row.Synthetic, Row.Name, 0, 20,
                  Guikit.Draw.Text_Color, Guikit.Draw.Muted_Text_Color,
                  Guikit.Draw.Border_Color, Guikit.Draw.Selection_Color,
                  Guikit.Draw.Text_Color);
               if View = Guikit.Item_Grid.Details then
                  Guikit.Item_Grid.Draw_Details_Row
                    (Result.Rectangles, Result.Text, Tips, Shell.Layout.Content_W, H, Cell, 20,
                     To_Unbounded_String (""), Row.Size_Text, Row.Kind_Text,
                     Row.Method_Text, Row.Path_Text, To_Unbounded_String (""),
                     To_Unbounded_String (""), Row.Synthetic, Guikit.Draw.Text_Color,
                     Guikit.Draw.Muted_Text_Color, Guikit.Draw.Border_Color);
               end if;
               Add_Accessibility
                 (Result.Accessibility, Guikit.Draw.Role_List_Item, Cell.X, Cell.Y,
                  Cell.Width, Cell.Height, Row.Name, Row.Kind_Text, Row.Focused, Row.Selected);
            end;
         end if;
      end loop;
   end Draw_Content;

   function Command_Palette_For (Shell : Archive.UI.Shell_Snapshot) return Guikit.Command_Palette.Palette is
      Palette  : Guikit.Command_Palette.Palette;
      Commands : Guikit.Command_Palette.Command_Vectors.Vector;
   begin
      for Row of Shell.Command_Palette.Rows loop
         Commands.Append
           (Guikit.Command_Palette.Command'
              (Id          => Archive.Commands.Command_Id'Pos (Row.Id),
               Identifier  => Row.Identifier,
               Label       => Row.Name,
               Description => Row.Description,
               Shortcut    => To_Unbounded_String (""),
               Enabled     => Row.Enabled,
               Icon        => Guikit.Command_Palette.No_Icon));
      end loop;

      Guikit.Command_Palette.Set_Configuration
        (Palette,
         (Line_Height    => Archive.UI.Default_Line_Height,
          Show_Icons     => False,
          Show_Shortcuts => False,
          Overlay        => True,
          Wrap_Selection => True,
          Placeholder    => Shell.Command_Palette_Label,
          Empty_State    => Shell.Status_Text,
          Title          => Shell.Command_Palette_Label));
      Guikit.Command_Palette.Set_Commands (Palette, Commands);
      Guikit.Command_Palette.Set_Query (Palette, To_String (Shell.Command_Palette_Filter));
      Guikit.Command_Palette.Select_First (Palette);
      Guikit.Command_Palette.Move_Selection (Palette, Shell.Command_Palette_Moves);
      return Palette;
   end Command_Palette_For;

   procedure Command_Palette_Box
     (Width, Height : Natural;
      X, Y, W, H    : out Natural) is
   begin
      X := Width / 5;
      Y := Height / 5;
      W := (Width * 3) / 5;
      H := (Height * 3) / 5;
   end Command_Palette_Box;

   procedure Draw_Command_Palette
     (Result : in out Frame;
      Shell  : Archive.UI.Shell_Snapshot;
      W      : Natural;
      H      : Natural)
   is
      Palette : Guikit.Command_Palette.Palette := Command_Palette_For (Shell);
      Rects : Guikit.Draw.Rectangle_Command_Vectors.Vector;
      Text  : Guikit.Draw.Text_Command_Vectors.Vector;
      Icons : Guikit.Draw.Icon_Command_Vectors.Vector;
      Nodes : Guikit.Draw.Accessibility_Node_Vectors.Vector;
      Box_X, Box_Y, Box_W, Box_H : Natural;
   begin
      Command_Palette_Box (W, H, Box_X, Box_Y, Box_W, Box_H);
      Guikit.Command_Palette.Build_Frame
        (Palette, Box_X, Box_Y, Box_W, Box_H, W, H,
         Shell.Focus.Region = Archive.Model.Command_Palette_Focus, -1, -1,
         Rects, Text, Icons, Nodes);
      for Rect of Rects loop
         Result.Overlay_Rectangles.Append (Rect);
      end loop;
      for Line of Text loop
         Result.Overlay_Text.Append (Line);
      end loop;
      for Icon of Icons loop
         Result.Icons.Append (Icon);
      end loop;
      for Node of Nodes loop
         Result.Accessibility.Append (Node);
      end loop;
   end Draw_Command_Palette;

   procedure Append_Panel_Output
     (Result : in out Frame;
      Rects  : Guikit.Draw.Rectangle_Command_Vectors.Vector;
      Text   : Guikit.Draw.Text_Command_Vectors.Vector;
      Nodes  : Guikit.Draw.Accessibility_Node_Vectors.Vector)
   is
   begin
      for Rect of Rects loop
         Result.Overlay_Rectangles.Append (Rect);
      end loop;
      for Line of Text loop
         Result.Overlay_Text.Append (Line);
      end loop;
      for Node of Nodes loop
         Result.Accessibility.Append (Node);
      end loop;
   end Append_Panel_Output;

   procedure Settings_Panel_Box
     (Width, Height : Natural;
      X, Y, W, H    : out Natural) is
   begin
      X := Width / 6;
      Y := Height / 8;
      W := (Width * 2) / 3;
      H := (Height * 3) / 4;
   end Settings_Panel_Box;

   function Settings_Panel_For (Shell : Archive.UI.Shell_Snapshot) return Guikit.Settings_Panel.Panel is
      Panel  : Guikit.Settings_Panel.Panel;
      Fields : Guikit.Settings_Panel.Field_Vectors.Vector;

      function Bool_Value (Value : Boolean) return Archive.Types.UString is
      begin
         return To_Unbounded_String ((if Value then "true" else "false"));
      end Bool_Value;

      procedure Add_Section (Label : Archive.Types.UString) is
      begin
         Fields.Append
           (Guikit.Settings_Panel.Field'
              (Key           => Label,
               Label         => Label,
               Kind          => Guikit.Settings_Panel.Section,
               Value         => To_Unbounded_String (""),
               Option_Values => <>,
               Option_Labels => <>,
               Min           => 0,
               Max           => 0,
               Enabled       => True,
               Display       => <>,
               Help          => To_Unbounded_String ("")));
      end Add_Section;

      procedure Add_Toggle
        (Key   : String;
         Label : Archive.Types.UString;
         Value : Boolean)
      is
      begin
         Fields.Append
           (Guikit.Settings_Panel.Field'
              (Key           => To_Unbounded_String (Key),
               Label         => Label,
               Kind          => Guikit.Settings_Panel.Toggle,
               Value         => Bool_Value (Value),
               Option_Values => <>,
               Option_Labels => <>,
               Min           => 0,
               Max           => 0,
               Enabled       => True,
               Display       => <>,
               Help          => To_Unbounded_String ("")));
      end Add_Toggle;

      procedure Add_View_Choice is
         Values : Guikit.Settings_Panel.UString_Vectors.Vector;
         Labels : Guikit.Settings_Panel.UString_Vectors.Vector;
      begin
         Values.Append (To_Unbounded_String ("grid"));
         Values.Append (To_Unbounded_String ("compact"));
         Values.Append (To_Unbounded_String ("details"));
         Labels.Append (Shell.Settings.Grid_Label);
         Labels.Append (Shell.Settings.Compact_Label);
         Labels.Append (Shell.Settings.Details_Label);
         Fields.Append
           (Guikit.Settings_Panel.Field'
              (Key           => To_Unbounded_String ("default_view"),
               Label         => Shell.Settings.View_Label,
               Kind          => Guikit.Settings_Panel.Choice,
               Value         => To_Unbounded_String
                 (Archive.Settings.View_Mode_Token (Shell.Settings.Default_View)),
               Option_Values => Values,
               Option_Labels => Labels,
               Min           => 0,
               Max           => 0,
               Enabled       => True,
               Display       => <>,
               Help          => To_Unbounded_String ("")));
      end Add_View_Choice;
   begin
      Add_Section (Shell.Settings.General_Section_Label);
      Add_View_Choice;
      Add_Toggle
        ("directories_first", Shell.Settings.Directories_First_Label,
         Shell.Settings.Directories_First);
      Add_Toggle
        ("preview_visible", Shell.Settings.Preview_Visible_Label,
         Shell.Settings.Preview_Visible);
      Add_Section (Shell.Settings.Layout_Section_Label);
      Add_Toggle
        ("toolbar_visible", Shell.Settings.Toolbar_Visible_Label,
         Shell.Settings.Toolbar_Visible);
      Add_Toggle
        ("status_bar_visible", Shell.Settings.Status_Bar_Visible_Label,
         Shell.Settings.Status_Bar_Visible);

      Guikit.Settings_Panel.Set_Configuration
        (Panel,
         (Line_Height     => Archive.UI.Default_Line_Height,
          Title           => Shell.Settings.Title,
          Status          => Shell.Settings.Status_Text,
          Status_Is_Error => False,
          Switch_Tooltip  => To_Unbounded_String ("")));
      Guikit.Settings_Panel.Set_Fields (Panel, Fields);
      return Panel;
   end Settings_Panel_For;

   procedure Draw_Settings_Overlay
     (Result : in out Frame;
      Shell  : Archive.UI.Shell_Snapshot;
      W      : Natural;
      H      : Natural)
   is
      Panel  : Guikit.Settings_Panel.Panel := Settings_Panel_For (Shell);
      Rects  : Guikit.Draw.Rectangle_Command_Vectors.Vector;
      Text   : Guikit.Draw.Text_Command_Vectors.Vector;
      Nodes  : Guikit.Draw.Accessibility_Node_Vectors.Vector;
      Box_X, Box_Y, Box_W, Box_H : Natural;
   begin
      Settings_Panel_Box (W, H, Box_X, Box_Y, Box_W, Box_H);
      Guikit.Settings_Panel.Build_Frame
        (Panel, Box_X, Box_Y, Box_W, Box_H, W, H,
         Shell.Focus.Region = Archive.Model.Settings_Focus, -1, -1,
         Rects, Text, Nodes);
      Append_Panel_Output (Result, Rects, Text, Nodes);
   end Draw_Settings_Overlay;

   procedure Draw_Preview_Panel
     (Result : in out Frame;
      Shell  : Archive.UI.Shell_Snapshot;
      W      : Natural;
      H      : Natural)
   is
      Rows : Guikit.List_Panel.List_Panel_Row_Vectors.Vector;

      procedure Add_Row
        (Label  : Archive.Types.UString;
         Detail : Archive.Types.UString)
      is
      begin
         Rows.Append
           (Guikit.List_Panel.List_Panel_Row'
              (Label            => Label,
               Detail           => Detail,
               Shortcut         => To_Unbounded_String (""),
               Selected         => False,
               Enabled          => True,
               Label_Color      => Guikit.Draw.Text_Color,
               Has_Background   => False,
               Background_Color => Guikit.Draw.Pane_Color,
               Accent_Color     => Guikit.Draw.Border_Color,
               Shortcut_Color   => Guikit.Draw.Muted_Text_Color));
      end Add_Row;
   begin
      if Shell.Layout.Preview_W = 0 then
         return;
      end if;

      Add_Row (Shell.Preview_Panel.State_Text, To_Unbounded_String (""));
      if Length (Shell.Preview_Panel.Result.Text) > 0 then
         Add_Row (Shell.Preview_Panel.Result.Text, To_Unbounded_String (""));
      end if;
      if Length (Shell.Preview_Panel.Truncated_Text) > 0 then
         Add_Row (Shell.Preview_Panel.Truncated_Text, To_Unbounded_String (""));
      end if;

      Guikit.List_Panel.Draw_Frame
        (Result.Rectangles, Result.Text, Result.Accessibility,
         W, H, Shell.Layout.Preview_X + 8, Shell.Layout.Content_Y + 36,
         (if Shell.Layout.Preview_W > 16 then Shell.Layout.Preview_W - 16 else 0),
         (if Shell.Layout.Content_H > 44 then Shell.Layout.Content_H - 44 else 0),
         (Title               => Shell.Preview_Label,
          Empty_State         => Shell.Preview_Panel.State_Text,
          Line_Height         => Archive.UI.Default_Line_Height,
          Text_Padding        => 12,
          Show_Alternate_Rows => True),
         Rows,
         Draw_Chrome => False);
   end Draw_Preview_Panel;

   function Build (Shell : Archive.UI.Shell_Snapshot) return Frame is
      Result : Frame;
      W      : constant Natural := Shell.Layout.Content_W + Shell.Layout.Preview_W;
      H      : constant Natural := Shell.Layout.Status_Y + Shell.Layout.Status_H;
   begin
      Result.Layout :=
        (Width             => W,
         Height            => H,
         Toolbar_Height    => Shell.Layout.Toolbar_H,
         Bottom_Bar_Height => Shell.Layout.Status_H,
         Main_X            => 0,
         Main_Y            => Shell.Layout.Content_Y,
         Main_Width        => Shell.Layout.Content_W,
         Main_Height       => Shell.Layout.Content_H,
         Info_Pane_Width   => Shell.Layout.Preview_W,
         Command_X         => 0,
         Command_Y         => Shell.Layout.Breadcrumb_Y,
         Command_Width     => W,
         Command_Height    => Shell.Layout.Breadcrumb_H);

      Result.Rectangles.Append
        (Guikit.Draw.Rectangle_Command'
           (X => 0, Y => 0, Width => W, Height => H, Color => Guikit.Draw.Canvas_Color));
      Result.Rectangles.Append
        (Guikit.Draw.Rectangle_Command'
           (X => 0, Y => 0, Width => W, Height => Shell.Layout.Toolbar_H,
            Color => Guikit.Draw.Toolbar_Color));
      Result.Rectangles.Append
        (Guikit.Draw.Rectangle_Command'
           (X => 0, Y => Shell.Layout.Breadcrumb_Y, Width => W, Height => Shell.Layout.Breadcrumb_H,
            Color => Guikit.Draw.Pane_Color));
      Result.Rectangles.Append
        (Guikit.Draw.Rectangle_Command'
           (X => 0, Y => Shell.Layout.Content_Y, Width => Shell.Layout.Content_W,
            Height => Shell.Layout.Content_H, Color => Guikit.Draw.Main_Color));
      if Shell.Layout.Preview_W > 0 then
         Result.Rectangles.Append
           (Guikit.Draw.Rectangle_Command'
              (X => Shell.Layout.Preview_X, Y => Shell.Layout.Content_Y,
               Width => Shell.Layout.Preview_W, Height => Shell.Layout.Content_H,
               Color => Guikit.Draw.Pane_Color));
      end if;
      Result.Rectangles.Append
        (Guikit.Draw.Rectangle_Command'
           (X => 0, Y => Shell.Layout.Status_Y, Width => W, Height => Shell.Layout.Status_H,
            Color => Guikit.Draw.Bottom_Bar_Color));

      Add_Text (Result.Text, 12, 8, 220, 24, Shell.Title);
      Add_Text (Result.Text, 12, Shell.Layout.Content_Y + 8, Shell.Layout.Content_W - 24, 22,
                Shell.Content_View.Label);
      Add_Text (Result.Text, 12, Shell.Layout.Status_Y + 4, W - 24, 20, Shell.Status_Bar.Text,
                Guikit.Draw.Muted_Text_Color);
      Draw_Breadcrumb (Result, Shell, W, H);
      Draw_Content (Result, Shell, W, H);
      if Shell.Layout.Preview_W > 0 then
         Add_Text (Result.Text, Shell.Layout.Preview_X + 12, Shell.Layout.Content_Y + 8,
                   Shell.Layout.Preview_W - 24, 22, Shell.Preview_Label);
         Draw_Preview_Panel (Result, Shell, W, H);
      end if;

      for Button of Toolbar_Buttons (Shell, W) loop
         Guikit.Widgets.Draw_Button
           (Result.Rectangles, Result.Text, W, H, Button.X, Button.Y, Button.Width, Button.Height,
            Guikit.Draw.Input_Color, Guikit.Draw.Border_Color, Toolbar_Button_Padding,
            Button.Label, False, Archive.UI.Default_Line_Height,
            (if Button.Enabled then Guikit.Draw.Text_Color else Guikit.Draw.Disabled_Text_Color));
         Add_Accessibility
           (Result.Accessibility, Guikit.Draw.Role_Button, Button.X, Button.Y, Button.Width, Button.Height,
            Button.Label);
      end loop;

      if Shell.Toolbar_Overflow_Open then
         declare
            Rows : constant Toolbar_Button_Vectors.Vector := Toolbar_Overflow_Rows (Shell, W);
         begin
            if not Rows.Is_Empty then
               Guikit.Widgets.Draw_Menu_Panel
                 (Result.Overlay_Rectangles, W, H, Rows.First_Element.X, Rows.First_Element.Y,
                  Rows.First_Element.Width,
                  Rows.Last_Element.Y + Rows.Last_Element.Height - Rows.First_Element.Y,
                  Guikit.Draw.Overlay_Color, Guikit.Draw.Border_Color);
               for Row of Rows loop
                  Add_Text
                    (Result.Overlay_Text, Row.X + Toolbar_Button_Padding, Row.Y + 4,
                     Row.Width - 2 * Toolbar_Button_Padding, Archive.UI.Default_Line_Height, Row.Label,
                     (if Row.Enabled then Guikit.Draw.Text_Color else Guikit.Draw.Disabled_Text_Color));
                  Add_Accessibility
                    (Result.Accessibility, Guikit.Draw.Role_Button, Row.X, Row.Y, Row.Width, Row.Height,
                     Row.Label);
               end loop;
            end if;
         end;
      end if;

      if Shell.Dialog.Visible then
         Guikit.Widgets.Draw_Menu_Panel
           (Result.Overlay_Rectangles, W, H, W / 4, H / 4, W / 2, H / 4,
            Guikit.Draw.Overlay_Color, Guikit.Draw.Border_Color);
         Add_Text (Result.Overlay_Text, W / 4 + 16, H / 4 + 16, W / 2 - 32, 24, Shell.Dialog.Title);
         if Shell.Dialog.Takes_Path then
            --  The dialog's one field: the typed path with a caret after it,
            --  and what to do with it underneath.
            declare
               Line_H  : constant Positive := Archive.UI.Default_Line_Height;
               Field_X : constant Natural := W / 4 + 16;
               Field_Y : constant Natural := H / 4 + 56;
               Field_W : constant Natural := (if W / 2 > 32 then W / 2 - 32 else 0);
               Field_H : constant Natural := Line_H + 8;
               Typed_W : constant Natural :=
                 Guikit.Layout.Label_Pixel_Width
                   (To_String (Shell.Dialog.Text), Guikit.Layout.Caret_Advance_Width (Line_H));
            begin
               Guikit.Widgets.Draw_Input_Field
                 (Result.Overlay_Rectangles, W, H, Field_X, Field_Y, Field_W, Field_H,
                  Guikit.Draw.Input_Color, Guikit.Draw.Selection_Color);
               Add_Text (Result.Overlay_Text, Field_X + 6, Field_Y + 4, Field_W - 12, Line_H, Shell.Dialog.Text);
               Guikit.Widgets.Draw_Caret
                 (Result.Overlay_Rectangles, W, H, Natural'Min (Field_X + 6 + Typed_W, Field_X + Field_W - 4),
                  Field_Y + 4, 2, Line_H, Guikit.Draw.Text_Color);
               Add_Text
                 (Result.Overlay_Text, Field_X, Field_Y + Field_H + 8, Field_W, Line_H, Shell.Dialog.Hint,
                  Guikit.Draw.Muted_Text_Color);
            end;
         end if;
         Add_Accessibility
           (Result.Accessibility, Guikit.Draw.Role_Dialog, W / 4, H / 4, W / 2, H / 4,
            Shell.Dialog.Accessible_Name);
      elsif Shell.Overlay.Visible then
         if Shell.Overlay.Active = Archive.Model.Command_Palette_Overlay then
            Draw_Command_Palette (Result, Shell, W, H);
         elsif Shell.Overlay.Active = Archive.Model.Settings_Overlay then
            Draw_Settings_Overlay (Result, Shell, W, H);
         else
            Guikit.Widgets.Draw_Menu_Panel
              (Result.Overlay_Rectangles, W, H, W / 5, H / 5, (W * 3) / 5, (H * 3) / 5,
               Guikit.Draw.Overlay_Color, Guikit.Draw.Border_Color);
            Add_Text (Result.Overlay_Text, W / 5 + 16, H / 5 + 16, (W * 3) / 5 - 32, 24,
                      Shell.Overlay.Accessible_Name);
         end if;
      end if;

      Add_Accessibility (Result.Accessibility, Guikit.Draw.Role_Window, 0, 0, W, H, Shell.Title);
      Add_Accessibility (Result.Accessibility, Guikit.Draw.Role_Toolbar, 0, 0, W, Shell.Layout.Toolbar_H,
                         Shell.Title);
      Add_Accessibility (Result.Accessibility, Guikit.Draw.Role_List, 0, Shell.Layout.Content_Y,
                         Shell.Layout.Content_W, Shell.Layout.Content_H,
                         Shell.Content_View.Accessible_Name,
                         Focused => Shell.Focus.Region = Archive.Model.Content_Focus);
      Add_Accessibility (Result.Accessibility, Guikit.Draw.Role_Status, 0, Shell.Layout.Status_Y,
                         W, Shell.Layout.Status_H, Shell.Status_Bar.Accessible_Name);
      return Result;
   end Build;

   function To_Submission (Rendered : Frame) return Guikit.Vulkan.Submission_Batch is
      Text : Guikit.Draw.Text_Render_Result;
   begin
      Text.Status := Guikit.Draw.Text_Render_Font_Not_Loaded;
      return To_Submission (Rendered, Text);
   end To_Submission;

   function To_Submission
     (Rendered : Frame;
      Text     : Guikit.Draw.Text_Render_Result) return Guikit.Vulkan.Submission_Batch is
   begin
      return Guikit.Vulkan.Build_Submission
        (Rendered.Rectangles, Rendered.Triangles, Rendered.Icons,
         Rendered.Overlay_Rectangles, Rendered.Layout, Guikit.Draw.Theme_Dark, Text);
   end To_Submission;

   function Validate (Rendered : Frame) return Frame_Validation is
      Batch : constant Guikit.Vulkan.Submission_Batch := To_Submission (Rendered);
      Rects : constant Natural := Natural (Rendered.Rectangles.Length);
      Texts : constant Natural := Natural (Rendered.Text.Length) + Natural (Rendered.Overlay_Text.Length);
      Nodes : constant Natural := Natural (Rendered.Accessibility.Length);
   begin
      return
        (Valid               => Rendered.Layout.Width > 0
                                and then Rendered.Layout.Height > 0
                                and then Rects >= 5
                                and then Texts >= 4
                                and then Nodes >= 4
                                and then Natural (Batch.Vertices.Length) > 0,
         Rectangle_Count     => Rects + Natural (Rendered.Overlay_Rectangles.Length),
         Text_Count          => Texts,
         Accessibility_Count => Nodes,
         Vertex_Count        => Natural (Batch.Vertices.Length));
   end Validate;
end Archive.GUI_Frame;
