with Ada.Directories;
with Ada.Environment_Variables;

package body Archive.Fonts is

   --  Every host keeps its fonts somewhere else under some other name, so these
   --  are searches rather than paths. A list of Linux paths alone would leave
   --  macOS and Windows unable to draw a character.
   Mono_Candidates : constant array (Positive range <>) of access constant String :=
     [new String'("/usr/share/fonts/truetype/noto/NotoSansMono-Regular.ttf"),
      new String'("/usr/share/fonts/truetype/dejavu/DejaVuSansMono.ttf"),
      new String'("/usr/share/fonts/truetype/liberation/LiberationMono-Regular.ttf"),
      new String'("/usr/share/fonts/TTF/DejaVuSansMono.ttf"),
      new String'("/System/Library/Fonts/Menlo.ttc"),
      new String'("/System/Library/Fonts/Monaco.ttf"),
      new String'("C:\Windows\Fonts\consola.ttf"),
      new String'("C:\Windows\Fonts\cour.ttf")];

   Fallback_Candidates : constant array (Positive range <>) of access constant String :=
     [new String'("/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf"),
      new String'("/usr/share/fonts/truetype/noto/NotoSans-Regular.ttf"),
      new String'("/usr/share/fonts/TTF/DejaVuSans.ttf"),
      new String'("/System/Library/Fonts/Supplemental/Arial.ttf"),
      new String'("/System/Library/Fonts/Helvetica.ttc"),
      new String'("C:\Windows\Fonts\segoeui.ttf"),
      new String'("C:\Windows\Fonts\arial.ttf"),

      --  Colour emoji, and last on purpose. The chain is resolved by asking each
      --  font whether it maps a codepoint and taking the first that says yes, and
      --  an emoji font maps far more than emoji -- arrows, stars, the check mark.
      --  Ahead of the text fonts it would capture characters they draw perfectly
      --  well.
      --
      --  Only the layered kind is listed. Textrender draws a COLR/CPAL glyph from
      --  outlines and a palette, needing nothing from the caller; the bitmap kinds
      --  (Noto Color Emoji, Apple Color Emoji) hold PNGs and want a decoder, which
      --  this application does not carry.
      new String'("C:\Windows\Fonts\seguiemj.ttf"),
      new String'("/usr/share/fonts/truetype/twemoji/TwemojiMozilla.ttf"),
      new String'("/usr/share/fonts/TTF/TwemojiMozilla.ttf")];

   function Exists (Path : String) return Boolean is
      use type Ada.Directories.File_Kind;
   begin
      return Path /= ""
        and then Ada.Directories.Exists (Path)
        and then Ada.Directories.Kind (Path) = Ada.Directories.Ordinary_File;
   exception
      when others =>
         return False;
   end Exists;

   --  A font the user installed for themselves, which is where one lands on a
   --  machine without root.
   function User_Font (Leaf : String) return String is
   begin
      if not Ada.Environment_Variables.Exists ("HOME") then
         return "";
      end if;

      return Ada.Environment_Variables.Value ("HOME")
        & "/.local/share/fonts/" & Leaf;
   exception
      when others =>
         return "";
   end User_Font;

   function Primary return String is
   begin
      for Candidate of Mono_Candidates loop
         if Exists (Candidate.all) then
            return Candidate.all;
         end if;
      end loop;

      return "";
   end Primary;

   function Fallbacks return Guikit.Text.Font_Path_Vectors.Vector is
      Result : Guikit.Text.Font_Path_Vectors.Vector;
   begin
      for Candidate of Fallback_Candidates loop
         if Exists (Candidate.all) and then Candidate.all /= Primary then
            Result.Append (Candidate.all);
         end if;
      end loop;

      if Exists (User_Font ("TwemojiMozilla.ttf")) then
         Result.Append (User_Font ("TwemojiMozilla.ttf"));
      end if;

      return Result;
   end Fallbacks;

end Archive.Fonts;
