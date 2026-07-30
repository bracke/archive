with Guikit.Text;

--  Which fonts this application draws with on the machine it is running on.
--
--  The same shape as the file manager's and the launcher's: a monospaced primary
--  for the body text, then a fallback chain for the codepoints it lacks, ending
--  with colour emoji.
package Archive.Fonts is

   --  The monospaced font to draw with, or "" when the machine has none.
   --
   --  @return Path to the primary font.
   function Primary return String;

   --  Fonts consulted, in order, for codepoints the primary does not have.
   --
   --  @return Ordered fallback font paths that exist on this machine.
   function Fallbacks return Guikit.Text.Font_Path_Vectors.Vector;

end Archive.Fonts;
