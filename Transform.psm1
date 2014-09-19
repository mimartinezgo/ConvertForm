# PowerShell ConvertForm 
# Transform module
# Objet   : Regroupe des fonctions de transformation de 
#           code CS en code PowerShell.

#todo traduire commentaire Fr dans le code g�n�r�

Import-LocalizedData -BindingVariable TransformMsgs -Filename TransformLocalizedData.psd1 -EA Stop

 #Cr�ation du header
."$psScriptRoot\Tools\Add-Header.ps1"

function Convert-DictionnaryEntry($Parameters) 
{   #Converti un DictionnaryEntry en une string "cl�=valeur cl�=valeur..." 
  "$($Parameters.GetEnumerator()|% {"$($_.key)=$($_.value)"})"
}#Convert-DictionnaryEntry

function Backup-Collection($Collection,$Message)
{ #Sauvegarde dans un fichier temporaire unique le contenu de la collection de lignes en cours d'analyse
  if ( $DebugPreference -ne 'SilentlyContinue') 
  { 
     $TempFile = [IO.Path]::GetTempFileName()
     $Collection|Set-Content $TempFile
     Write-Debug $Message
     Write-Debug "Sauvegarde dans le fichier temporaire : $TempFile"
  }
}

Function Add-LoadAssembly{
 param (
  [System.Collections.ArrayList] $Liste,
  [String[]] $Assemblies
 )
 #Charge une liste d'assemblies .NET 
 #On les suppose pr�sent dans le GAC
 #todo-Vnext : ceux n'�tant pas dans le GAC :   Add-Type -Path 'FullPath\filename.dll' 
 foreach ($Assembly in $Assemblies)
 { [void]$Liste.Add("Add-Type -AssemblyName $Assembly") }
 [void]$Liste.Add('')
}

Function Add-EventComponent([String] $ComponentName, [String] $EventName)
{ #Cr�e et ajoute un �v�nement d'un composant.
  #Par d�faut le scriptbloc g�n�r� affiche un message d'information

  $UnderConstruction = "[void][System.Windows.Forms.MessageBox]::Show(`"$($TransformMsgs.AddEventComponent)`")"
   #La syntaxe d'ajout d'un d�l�gu� est : Add_NomEv�n�ment 
   # o� le nom de l'�v�nement est celui du SDK .NET
   #On construit le nom de la fonction appell�e par le gestionnaire d'�v�nement
  $OnEvent_Name="On{0}_{1}" -f ($EventName,$ComponentName)
  $Fonction ="function $OnEvent_Name {{`r`n`t{0}`r`n}}`r`n" -f ($UnderConstruction)
   #On double le caract�re '{' afin de pouvoir l'afficher
  $EvtHdl= "`${0}.Add_{1}( {{ {2} }} )`r`n" -f ($ComponentName, $EventName, $OnEvent_Name)
# Here-string    
@"
$Fonction
$EvtHdl
"@
}

function Add-SpecialEventForm{
 param(
  [String] $FormName,
  [switch] $HideConsole
 )
  # Ajoute des m�thodes d'�v�nement sp�cifiques � la forme principale
  #FormClosing
    # Permet � l'utilisateur de : 
    #   -d�terminer la cause de la fermeture
    #   -autoriser ou non la fermeture

 $Ent�te = 'function OnFormClosing_{0}{{' -F $FormName
 $Close  = '${0}.Add_FormClosing( {{ OnFormClosing_{0}}} )' -F $FormName

 $CallHidefnct=""
   #On affiche la fen�tre, mais on cache la console 
 If ($HideConsole)
  {$CallHidefnct="Hide-Window;"}
   #Replace au premier plan la fen�tre en l'activant.
   # Form1.topmost=$true est inop�rant
 $Shown  = '${0}.Add_Shown({{{1}${0}.Activate()}})' -F $FormName,$CallHidefnct

# Here-string  
@"
$Ent�te 
`t# `$this parameter is equal to the sender (object)
`t# `$_ is equal to the parameter e (eventarg)

`t# The CloseReason property indicates a reason for the closure :
`t#   if ((`$_).CloseReason -eq [System.Windows.Forms.CloseReason]::UserClosing)

`t#Sets the value indicating that the event should be canceled.
`t(`$_).Cancel= `$False
}
$Close
$Shown
"@
}

function Add-GetScriptDirectory{
Write-Debug "Add-GetScriptDirectory" 
@"

function Get-ScriptDirectory
{ #Return the directory name of this script
  `$Invocation = (Get-Variable MyInvocation -Scope 1).Value
  Split-Path `$Invocation.MyCommand.Path
}

`$ScriptPath = Get-ScriptDirectory
"@         
}#Add-GetScriptDirectory

function Add-ManageResources{
 #Ajoute le code g�rant un fichier de ressources et ce � l'aide d'une "here-string"
  # 1 fonction
  # 2 test d'existence du fichier
  # 3 r�cup�ration dans une hastable des ressources de la Winform

 param (
  [string] $SourceName
 )
Write-Debug "Add-ManageResources $SourceName.resources" 

@"

`$ResourcesPath= Join-Path `$ScriptPath "$SourceName.resources"
if ( !(Test-Path `$ResourcesPath))
{
  Write-Error `"$($TransformMsgs.ManageResourcesError)`"
  break; 
}
  #Gestion du fichier des ressources
`$Reader = new-Object System.Resources.ResourceReader(`$ResourcesPath)
`$Resources=@{}
`$Reader.GetEnumerator()|% {`$Resources.(`$_.Name)=`$_.value}
 
 # Cr�ation des composants
"@         
}#Add-ManageResources

function Add-ManagePropertiesResources {
 param (
  [string] $SourceName
 )
Write-Debug "Add-ManagePropertiesResources $SourceName.resources"
 
@"

`$ResourcesPath= Join-Path `$ScriptPath "$SourceName.resources"
if ( !(Test-Path `$ResourcesPath))
{
  Write-Error `"$($TransformMsgs.ManageResourcesError)`"
  break; 
}
  #Gestion du fichier des ressources des propi�t�s du projet
`$PropertiesReader = new-Object System.Resources.ResourceReader(`$ResourcesPath)
`$PropertiesResources=@{}
`$PropertiesReader.GetEnumerator()|% {`$PropertiesResources.(`$_.Name)=`$_.value}

"@                  
}#Add-ManagePropertiesResources

function Convert-Enum([String] $Enumeration)
{ #Converti une valeur d'�num�ration
  # un.deux.trois en [un.deux]::trois
 $Enumeration = $Enumeration.trim()
  # recherche (et capture) en fin de cha�ne un mot pr�c�d� d'un point lui-m�me pr�c�d� de n'importe quel caract�res
 $Enumeration -replace '(.*)\.(\w+)$', '[$1]::$2'
}

function Select-ParameterEnumeration([String]$NomEnumeration, [String] $Parametres)
{ #Voir le fichier  "..\Documentations\Analyse des propri�t�s.txt"
 #G�re les propri�t�s Font et Anchor

  $Valeurs= $Parametres.Split('|')
  $NbValeur = $Valeurs.Count
   
   #Une seule valeur, on la convertie
  if ($NbValeur -eq 1 )
  { return Convert-Enum $Parametres} 

   #Valeur 1 :
   #         ((Nom.Enumeration)((Nom.Enumeration.VALEUR
    # recherche (et capture) en fin de cha�ne un mot pr�c�d� d'un point lui-m�me pr�c�d� de n'importe quel caract�res
  $Valeurs[0]= ($Valeurs[0] -replace '^.*\.(.*)$', '$1').Trim()
 
   #Valeur 2..n :
   #     Nom.Enumeration.VALEUR)    
   # recherche (et capture) en fin de cha�ne une parenth�se pr�c�d�e de caract�res uniquement pr�c�d�s d'un point lui-m�me pr�c�d� de n'importe quel caract�res
  for ($i=1;$i -le $NbValeur-2;$i++)
  { $Valeurs[$i]= ($Valeurs[$i] -replace '^.*\.([a-zA-Z]*)\)$', '$1').Trim() }

   #Derni�re valeur  :
   #         Nom.Enumeration.VALEUR))  
   # ou      Nom.Enumeration.VALEUR)))  
   # recherche (et capture) en fin de cha�ne deux parenth�ses pr�c�d�es de caract�res ou de chiffre uniquement pr�c�d�s d'un point lui-m�me pr�c�d� de n'importe quel caract�res
  $Valeurs[$NbValeur-1]= ($Valeurs[$NbValeur-1] -replace '^.*\.([a-zA-Z0-9]+)\)+$', '$1').Trim()
  return "[$NomEnumeration]`"{0}`"" -F ([string]::join(',', $Valeurs))
}

function Select-PropertyFONT([System.Text.RegularExpressions.Match] $MatchStr)
{ #Analyse une d�claration d'une propri�t� Font
   #Pour la cha�ne:  $label1.Font = New-Object System.Drawing.Font("Arial Black", 9.75F, System.Drawing.FontStyle.Bold, System.Drawing.GraphicsUnit.Point, ((byte)(0)))
	# $MatchStr contient 4 groupes :
	#  0- la ligne compl�te
	#  1- $label1
	#  2- .Font = New-Object System.Drawing.Font(
	#  3- "Arial Black", 9.75F, System.Drawing.FontStyle.Bold, System.Drawing.GraphicsUnit.Point, ((byte)(0))

    #R�cup�re les param�tres du constructeur
  $Parametres= [Regex]::Split($MatchStr.Groups[3].value,',')
    #Le premier est tjr le nom de la fonte de caract�re
    #Le second est tjr la taille de la fonte de caract�re dans ce cas on supprime le caract�re 'F' 
    #indiquant un type double
  $Parametres[1]=$Parametres[1] -replace 'F',''
  
   #Teste les diff�rentes signatures de constructeurs
   #On parcourt toute la liste du nombre de param�tre possibles, les uns � la suite des autres.
  Switch ($Parametres.count)
  { 
    {$_ -eq 3} {  #Est-ce un param�tre de type System.Drawing.GraphicsUnit ?
                 if ( $Parametres[2].Contains('System.Drawing.GraphicsUnit') )
         		 {$Parametres[2]=Convert-Enum $Parametres[2]}
         		   #si non c'est donc un param�tre de type System.Drawing.FontStyle ?
       			 else { $Parametres[2]=Select-ParameterEnumeration 'System.Drawing.FontStyle' $Parametres[2] }
     		   }

    {$_ -ge 4} {  #Le troisi�me est tjr de type FontStyle
   	   			  #Le quatri�me est tjr de type GraphicsUnit
                 $Parametres[2]= Select-ParameterEnumeration 'System.Drawing.FontStyle' $Parametres[2]
                 $Parametres[3]=Convert-Enum $Parametres[3]
               }
                 
    {$_ -ge 5} {  #On r�cup�re uniquement la valeur du param�tre : ((byte)(123))
                  # Un ou plusieurs chiffres :                        [0-9]+
                 $Parametres[4]=$Parametres[4] -replace '\(\(byte\)\(([0-9]+)\)\)', '$1' 
               }

    #6 Le sixi�me (true - false) est trait� par la suite dans le script principal

                  #Pb :/
    {$_ -ge 7} { throw (new-object ConvertForm.CSParseException( ('Unexpected case : {0}' -f ($MatchStr.Groups[3].value)))) }
  }
  
  return $Parametres
}
function Select-PropertyANCHOR([System.Text.RegularExpressions.Match] $MatchStr)
{ #Analyse une d�claration d'une propri�t� Anchor
   #Pour la cha�ne: $comboBox1.Anchor = ((System.Windows.Forms.AnchorStyles)((((System.Windows.Forms.AnchorStyles.Top | System.Windows.Forms.AnchorStyles.Bottom)| System.Windows.Forms.AnchorStyles.Left)| System.Windows.Forms.AnchorStyles.Right)));

	# $MatchStr contient 4 groupes :
	#  0- la ligne compl�te
	#  1- $comboBox1
	#  2- .Anchor = ((System.Windows.Forms.AnchorStyles)
	#  3- (((System.Windows.Forms.AnchorStyles.Top | System.Windows.Forms.AnchorStyles.Bottom)| System.Windows.Forms.AnchorStyles.Left)| System.Windows.Forms.AnchorStyles.Right));

 #Peut �tre cod� dans l'appelant mais cela documente un peu plus
 return Select-ParameterEnumeration 'System.Windows.Forms.AnchorStyles' $MatchStr.Groups[3].value
}

function Select-PropertyShortcutKeys([System.Text.RegularExpressions.Match] $MatchStr)
{ #Analyse une d�claration d'une propri�t� ShortcutKeys
   #Pour la cha�ne: this.toolStripMenuItem2.ShortcutKeys = ((System.Windows.Forms.Keys)((System.Windows.Forms.Keys.Alt | System.Windows.Forms.Keys.A)));

	# $MatchStr contient 4 groupes :
	#  0- la ligne compl�te
	#  1- $comboBox1
	#  2- .ShortcutKeys = ((System.Windows.Forms.Keys)
	#  3- ((System.Windows.Forms.Keys.Alt | System.Windows.Forms.Keys.A)));

 #Peut �tre cod� dans l'appelant mais cela documente un peu plus
 return Select-ParameterEnumeration 'System.Windows.Forms.Keys' $MatchStr.Groups[3].value
}

function Select-ParameterRGB([System.Text.RegularExpressions.Match] $MatchStr)
{ #Analyse les param�tres d'un appel de la m�thode FromArgb
   #Pour la cha�ne:  $Case�Cocher.FlatAppearance.MouseDownBackColor = System.Drawing.Color.FromArgb(((int)(((byte)(192)))), ((int)(((byte)(255)))), ((int)(((byte)(192)))))
	# $MatchStr contient 4 groupes :
	#  0- la ligne compl�te
	#  1- $Case�Cocher.FlatAppearance.MouseDownBackColor
	#  2-  = System.Drawing.Color.FromArgb(
	#  3- ((int)(((byte)(192)))), ((int)(((byte)(255)))), ((int)(((byte)(192))))
	 
    #R�cup�re les 3 param�tres
  $Parametres= [Regex]::Split($MatchStr.Groups[3].value,',')
  for ($i=0; $i -lt $Parametres.count; $i++)
	  # On r�cup�re uniquement la valeur du param�tre : ((int)(((byte)(192))))
	  #Recherche ( et capture) en d�but de chaine une suite de caract�re suivis d'une parenth�se suivi de 
	  #un ou plusieurs chiffres suivis par une ou plusieurs parenth�ses
  { $Parametres[$i]=$Parametres[$i]  -replace '^(.*)\(([0-9]+)\)+', '$2' }
   
  return $Parametres
}

function ConvertTo-StringBuilder([System.Text.RegularExpressions.Match] $MatchStr, [Array] $NumerosOrdonnes)
 {  #On reconstruit le d�but d'une cha�ne � partir d'une expression pars�e
   # $NumerosOrdonnes : Contient les num�ros des groupes � ins�rer dans la nouvelle cha�ne
   $Result=new-object System.Text.StringBuilder
   foreach ($Num in $NumerosOrdonnes)
   { [void]$Result.Append($MatchStr.Groups[$Num].value) }
   return $Result
 }
 
function ConvertTo-Line([System.Text.RegularExpressions.Match] $MatchStr, [Array] $NumerosOrdonnes,[string[]] $Parametres )
{ #Utilis� pour reconstruire une propriet�.

   #On reconstruit l'int�gralit� d'un cha�ne pars�e et transform�e
  $Sb=ConvertTo-StringBuilder $MatchStr $NumerosOrdonnes
  [void]$Sb.Append( [string]::join(',', $Parametres)) 
  return $Sb.ToString()
}

function New-FilesName{
  #Construit les paths et noms de fichier � partir de $Source et $Destination
 param(
   [string] $ScriptPath,
    
   [System.IO.FileInfo]$SourceFI,
   
    #PSPathInfo ou string
   $Destination
 )

  #Le fichier de ressource poss�de une autre construction que le nom du fichier source
  #On garde le nom de la Form car on peut avoir + fichiers .Designer.cs
   # en entr�e                 : -Source C:\VS\Projet\PS\Form1.Designer.cs -Destination C:\Temp
   # fichier ressource associ� : C:\VS\Projet\PS\Form1.resx   
   #
   # fichier script g�n�r�     : C:\Temp\Form1.ps1     
   # fichier de log g�n�r�     : C:\Temp\Form1.resources.Log
   # fichier ressource g�n�r�  : C:\Temp\Form1.resources
      
  $ProjectPaths=@{
     Source=$SourceFI.FullName
     SourcePath = $SourceFI.DirectoryName
     SourceName = ([System.IO.Path]::GetFilenameWithoutExtension($SourceFI.FullName)) -replace '.designer',''
  }
 
  if ($PSBoundParameters.ContainsKey('Destination'))
  { 
      #R�cup�re le nom de r�pertoire analys�
     $ProjectPaths.Destination=$Destination.GetFileName()
  }
  else
  { 
      #On utilise le r�pertoire du fichier source
     $ProjectPaths.Destination=$ProjectPaths.SourcePath
  }
  
   #Construit le nom � partir du nom de fichier source
  $ProjectPaths.Destination+="\$($ProjectPaths.SourceName).ps1"
  
  $DestinationFI=New-object System.IO.FileInfo $ProjectPaths.Destination  
    
  $ProjectPaths.DestinationPath = $DestinationFI.DirectoryName
  $ProjectPaths.DestinationName = ([System.IO.Path]::GetFilenameWithoutExtension($DestinationFi.FullName))

  Write-Debug 'BuildFiles ProjectPaths :' ; Convert-DictionnaryEntry $ProjectPaths|Foreach {Write-Debug $_}
  Write-Verbose ($TransformMsgs.SourcePath-F $ProjectPaths.Source)
  Write-Verbose ($TransformMsgs.DestinationPath -F $ProjectPaths.Destination)
  
  $ProjectPaths 
} #New-FilesName

function New-ResourcesFile{
#Compile le fichier contenant les ressources d'un formulaire, ex : Form1.resx
  [CmdletBinding()] 
 param (
  $ProjectPaths,
  [switch] $isLiteral
 ) 
  
  Write-Verbose 'Compile les ressources'
   #On g�n�re le fichier de ressources
   #todo + versions de resgen ?
   #   http://blogs.msdn.com/b/visualstudio/archive/2010/06/18/resgen-exe-error-an-attempt-was-made-to-load-a-program-with-an-incorrect-format.aspx
   #        connect.microsoft.com/VisualStudio/feedback/details/532584/error-when-compiling-resx-file-seems-related-to-beta2-bug-5252020
   #  http://stackoverflow.com/questions/9190885/could-not-load-file-or-assembly-system-drawing-or-one-of-its-dependencies-erro
  $Resgen="$psScriptRoot\ResGen.exe" 
   #todo suppose que psScriptRoot ne contient pas de globbing 
  if ( !(Test-Path $Resgen))
  { Write-Error ($TransformMsgs.ResgenNotFound -F $Resgen) }
  else
  {
	 $SrcResx = Join-Path $ProjectPaths.SourcePath ($ProjectPaths.SourceName+'.resx')
     $DestResx = Join-Path $ProjectPaths.DestinationPath ($ProjectPaths.SourceName+'.resources')
     $Log="$DestResx.log"
     'Resgen','SrcResx','DestResx','Log'|
       Get-Variable |
       Foreach { Write-Debug ('{0}={1}' -F $_.Name,$_.Value) }
     
     if ($isLiteral)
     { $FileResourceExist=Test-Path -LiteralPath $SrcResx }
     else
     { $FileResourceExist=Test-Path -Path $SrcResx }
	 
     if ($FileResourceExist)
	 {
	    #Redirige le handle d'erreur vers le handle standard de sortie
	   $ResultExec=.$Resgen $SrcResx $DestResx 2>&1
	   if ($LastExitCode -ne 0)
	   { Write-Error ($TransformMsgs.CreateResourceFileError -F $LastExitCode,$log) }
	   else 
       { Write-Verbose ($TransformMsgs.CreateResourceFile -F $DestResx) }
       
       try {
         if ($isLiteral)
         { $ResultExec|Out-File -Literal $Log -Width 999 }
         else
         { $ResultExec|Out-File -FilePath $Log -Width 999 }
       }catch {
          Write-Warning ($TransformMsgs.CreateLogFileError -F $Log)
       } 
	 }
     else
     { Write-Error ($TransformMsgs.ResourceFileNotFound -F $SrcResx) }
  } 
} #New-ResourcesFile

function Add-ErrorProvider([String] $ComponentName, [String] $FormName)
{ #Ajoute le texte suivant apr�s la ligne de cr�ation de la form,
  #le component ErrorProvider r�f�rence la Form contenant les composants qu'il doit g�rer

# Here-string  
@"
`#
`# $ComponentName
`#
$('${0}.ContainerControl = ${1}' -F $ComponentName,$FormName)

"@
} #Add-ErrorProvider

function Add-TestApartmentState {
  #Le switch -STA est indiqu�, on ajoute un test sur le mod�le du thread courant.
@"

 # The -STA parameter is required
if ([System.Threading.Thread]::CurrentThread.GetApartmentState() -ne [System.Threading.ApartmentState]::STA )
{ Throw (new-object System.Threading.ThreadStateException("$($TransformMsgs.NeedSTAthreading)")) }

"@
} #Add-TestApartmentState

function Clear-KeyboardBuffer {
 while ($Host.UI.RawUI.KeyAvailable) 
 { $null=$Host.UI.RawUI.ReadKey('NoEcho,IncludeKeyDown, IncludeKeyUp')}
}

function Read-Choice{
 #On ne localise pas, Anglais par d�faut 
  param(
      $Caption, 
      $Message,
        [ValidateSet('Yes','No')]
      $DefaultChoice='No'
  )
  
  Clear-KeyboardBuffer
  $Yes = New-Object System.Management.Automation.Host.ChoiceDescription '&Yes'
  $No = New-Object System.Management.Automation.Host.ChoiceDescription '&No'
  $Choices = [System.Management.Automation.Host.ChoiceDescription[]]($Yes,$No)
  $Host.UI.PromptForChoice($Caption,$Message,$Choices,([byte]($DefaultChoice -eq 'No')))
}

# todo function Read-Resources {
# #todo http://msdn.microsoft.com/fr-fr/library/t69a74ty%28v=vs.90%29.aspx
# # Lit le fichier resx du r�pertoire properties du projet : TestFrm.Properties.Resources         
#     if ( !(Test-Path $ResourcesPath))
#   {
#     Write-Error "Le fichier de ressources n'existe pas : $ResourcesPath"
#     break; 
#   }
# 
#   resgen G:\PS\ConvertForm\TestsWinform\Base\Properties\Resources.resx $env:temp
# 
#   $ResourcesPath= Join-Path $ScriptPath "$env:temp($Name).resources"
#     #Gestion du fichier des ressources
#   $Reader = new-Object System.Resources.ResourceReader($ResourcesPath)
#   $Resources=@{}
#   $Reader.GetEnumerator()|% {$Resources.($_.Name)=$_.value}
#   if ($Resources.Count -ne 0)
#   {return $Resources}          
#}

#Functions Windows
function Add-Win32FunctionsType {
@"  
# Possible value for the nCmdShow parameter
# SW_HIDE = 0;
# SW_SHOWNORMAL = 1;
# SW_NORMAL = 1;
# SW_SHOWMINIMIZED = 2;
# SW_SHOWMAXIMIZED = 3;
# SW_MAXIMIZE = 3;
# SW_SHOWNOACTIVATE = 4;
# SW_SHOW = 5;
# SW_MINIMIZE = 6;
# SW_SHOWMINNOACTIVE = 7;
# SW_SHOWNA = 8;
# SW_RESTORE = 9;
# SW_SHOWDEFAULT = 10;
# SW_MAX = 10
                     
`$signature = @'
 [DllImport("user32.dll")]
 public static extern bool ShowWindowAsync(IntPtr hWnd, int nCmdShow);
'@
Add-Type -MemberDefinition `$signature -Name 'Win32ShowWindowAsync' -Namespace Win32Functions

"@
} #Add-Win32FunctionsType

function Add-Win32FunctionsWrapper {
@'
function Show-Window([IntPtr] $WindowHandle=(Get-Process -Id $pid).MainWindowHandle){ 
 #Displays in the foreground, the window with the handle $WindowHandle   
   $SW_SHOWNORMAL = 1
   $null=[Win32Functions.Win32ShowWindowAsync]::ShowWindowAsync($WindowHandle,$SW_SHOWNORMAL) 
}

function Hide-Window([IntPtr] $WindowHandle=(Get-Process �id $pid).MainWindowHandle) {
 #Hide the window with the handle WindowHandle
 #The application is no longer available in the taskbar and in the task manager.
   $SW_HIDE = 0
   $null=[Win32Functions.Win32ShowWindowAsync]::ShowWindowAsync($WindowHandle,$SW_HIDE)
}

'@
} #Add-Win32FunctionsWrapper

New-Variable ChoiceNO -Value ([int]1) -EA SilentlyContinue
Export-ModuleMember -Variable ChoiceNO -Function * 
