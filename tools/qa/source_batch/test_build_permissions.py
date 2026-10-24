"""Execute the real permission extractor without executing the build script."""
from pathlib import Path
import shutil
import subprocess
import unittest

class BuildPermissionTests(unittest.TestCase):
    def test_actual_powershell_extractor_uses_xml_nodes_not_shadowed_name_attributes(self):
        script=Path(__file__).with_name('build.ps1').resolve()
        code=r'''
$tokens=$null; $parseErrors=$null
$ast=[System.Management.Automation.Language.Parser]::ParseFile($args[0],[ref]$tokens,[ref]$parseErrors)
if($parseErrors.Count){throw 'parse_failed'}
$definition=$ast.Find({param($n) $n -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -eq 'Get-QaManifestPermissions'},$true)
if($null -eq $definition){throw 'function_missing'}
. ([ScriptBlock]::Create($definition.Extent.Text))
[xml]$internet='<manifest xmlns:android="http://schemas.android.com/apk/res/android"><uses-permission android:name="android.permission.INTERNET"/></manifest>'
if('android.permission.INTERNET' -notin @(Get-QaManifestPermissions $internet)){throw 'missed_internet'}
[xml]$offline='<manifest xmlns:android="http://schemas.android.com/apk/res/android"><uses-permission android:name="android.permission.WAKE_LOCK"/><application android:name="android.permission.INTERNET"/></manifest>'
if('android.permission.INTERNET' -in @(Get-QaManifestPermissions $offline)){throw 'wrong_scope'}
[xml]$sdk='<manifest xmlns:a="http://schemas.android.com/apk/res/android"><uses-permission-sdk-23 a:name="android.permission.INTERNET"/></manifest>'
if('android.permission.INTERNET' -notin @(Get-QaManifestPermissions $sdk)){throw 'missed_sdk_permission'}
if(@(Get-QaManifestPermissions ([xml]'<manifest/>')).Count -ne 0){throw 'empty_failed'}
'permission_extractor_actual_positive_negative_pass'
'''
        # Pass the path through a literal script parameter, never shell interpolation.
        command='& { param($sourcePath) '+code.replace('$args[0]','$sourcePath')+' } '+"'"+str(script).replace("'","''")+"'"
        result=subprocess.run([shutil.which('pwsh') or 'pwsh','-NoProfile','-Command',command],capture_output=True,timeout=15)
        self.assertEqual(result.returncode,0,result.stderr.decode('utf-8','replace'))
        self.assertIn(b'permission_extractor_actual_positive_negative_pass',result.stdout)

if __name__=='__main__':unittest.main()
