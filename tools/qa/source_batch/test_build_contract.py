"""Execute the real PS plan and Groovy QA policy, without Gradle/Android builds."""
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest


class BuildContractTests(unittest.TestCase):
    def test_real_powershell_plan_covers_all_abis_offline_modes_and_exact_version(self):
        source = Path(__file__).with_name('build.ps1').resolve()
        code = r'''
param($source)
$tokens=$null; $errors=$null
$ast=[System.Management.Automation.Language.Parser]::ParseFile($source,[ref]$tokens,[ref]$errors)
if($errors.Count){throw 'parse_failed'}
$definition=$ast.Find({param($n) $n -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -eq 'Get-QaBuildPlan'},$true)
if($null -eq $definition){throw 'plan_missing'}
. ([ScriptBlock]::Create($definition.Extent.Text))
$expected=@{'android-arm'='armeabi-v7a';'android-arm64'='arm64-v8a';'android-x64'='x86_64'}
foreach($target in $expected.Keys){foreach($offline in @($false,$true)){
  $plan=Get-QaBuildPlan $target 20591 '0.4.5-parserqa.arm.3' $offline
  $flavor=if($offline){'parserQaOffline'}else{'parserQa'}
  if($plan.Abi -ne $expected[$target] -or $plan.Flavor -ne $flavor -or $plan.ExpectedVersionCode -ne 20591){throw 'identity_failed'}
  if($plan.ApkRelativePath -ne "build/app/outputs/flutter-apk/app-$($flavor.ToLowerInvariant())-debug.apk"){throw 'path_failed'}
  $flags=$plan.FlutterArguments
  if('--split-per-abi' -in $flags -or '--android-project-arg=disable-abi-filtering=true' -notin $flags){throw 'abi_flags_failed'}
  if($flags[[array]::IndexOf($flags,'--target-platform')+1] -ne $target){throw 'target_failed'}
  $value=$offline.ToString().ToLowerInvariant()
  if("--dart-define=KAZUMI_QA_LAUNCH_ONLY=$value" -notin $flags -or "--android-project-arg=kazumiQaLaunchOnly=$value" -notin $flags){throw 'offline_failed'}
  if('--build-number=20591' -notin $flags -or '--android-project-arg=kazumiParserQa=true' -notin $flags){throw 'version_failed'}
}}
foreach($bad in @('android-arm,android-x64','bad','')){
  $rejected=$false;try{$null=Get-QaBuildPlan $bad 20591 '0.4.5-parserqa.arm.3' $false}catch{$rejected=$true}
  if(-not $rejected){throw 'target_not_rejected'}
}
foreach($bad in @(0,2100000001)){
  $rejected=$false;try{$null=Get-QaBuildPlan 'android-arm' $bad '0.4.5-parserqa.arm.3' $false}catch{$rejected=$true}
  if(-not $rejected){throw 'version_not_rejected'}
}
$rejected=$false;try{$null=Get-QaBuildPlan 'android-arm' 20591 'unsafe&name' $false}catch{$rejected=$true}
if(-not $rejected){throw 'name_not_rejected'}
'qa_plan_actual_matrix_and_negative_pass'
'''
        with tempfile.TemporaryDirectory() as directory:
            script = Path(directory) / 'plan.ps1'
            script.write_text(code, encoding='utf-8')
            result = subprocess.run([shutil.which('pwsh') or 'pwsh', '-NoProfile', '-File', str(script), str(source)], capture_output=True, timeout=15)
        self.assertEqual(result.returncode, 0, result.stderr.decode('utf-8', 'replace'))
        self.assertIn(b'qa_plan_actual_matrix_and_negative_pass', result.stdout)

    def test_real_groovy_policy_clears_fat_defaults_and_preserves_non_qa_flavor(self):
        repo = Path(__file__).resolve().parents[3]
        pinned = Path(r'C:\Users\hentai\Documents\Codex\2026-10-02\task\toolchain\gradle-user-home\wrapper\dists\gradle-8.14.5-all')
        lib = Path(os.environ['KAZUMI_QA_GRADLE_LIB']) if os.environ.get('KAZUMI_QA_GRADLE_LIB') else next(pinned.glob('*/gradle-8.14.5/lib'))
        java = Path(os.environ.get('JAVA_HOME', r'C:\Program Files\Java\jdk-21')) / 'bin/java.exe'
        code = r'''
import org.gradle.api.GradleException
class FakeProject { Map props; Object findProperty(String name) { props[name] } }
class Flavors { List values; void configureEach(Closure c) { values.each { c.call(it) } } }
def policy = new File(args[0])
def make = { Map props ->
  def filters = { new Expando(abiFilters: new LinkedHashSet(['armeabi-v7a','arm64-v8a','x86_64'])) }
  def flavors = ['parserQa','parserQaOffline','untouched'].collect { new Expando(name:it,ndk:filters()) }
  def extension = new Expando(defaultConfig:new Expando(ndk:filters()),productFlavors:new Flavors(values:flavors))
  def binding = new Binding([project:new FakeProject(props:props),ext:[:]])
  new GroovyShell(binding).evaluate(policy)
  [extension:extension,flavors:flavors,apply:binding.getVariable('ext').configureParserQaAbi]
}
def props = [kazumiParserQa:'true','disable-abi-filtering':'true']
['android-arm':'armeabi-v7a','android-arm64':'arm64-v8a','android-x64':'x86_64'].each { target, abi ->
  def fixture=make(props+['target-platform':target])
  assert fixture.apply(fixture.extension)==abi
  assert fixture.extension.defaultConfig.ndk.abiFilters==([abi] as Set)
  assert fixture.flavors.take(2).every { it.ndk.abiFilters==([abi] as Set) }
  assert fixture.flavors.last().ndk.abiFilters.size()==3
}
def invalid = [[kazumiParserQa:'false'],[kazumiTv:'true'],['target-platform':null],
  ['target-platform':'android-arm,android-x64'],['target-platform':'unknown'],
  ['disable-abi-filtering':null],['disable-abi-filtering':'false'],['split-per-abi':'true'],['split-per-abi':'unknown']]
invalid.each { change ->
  def fixture=make(props+['target-platform':'android-arm']+change)
  def rejected=false
  try { fixture.apply(fixture.extension) } catch(GradleException expected) { rejected=true }
  assert rejected
  assert fixture.extension.defaultConfig.ndk.abiFilters.size()==3
}
println 'qa_actual_groovy_policy_matrix_and_negative_pass'
'''
        with tempfile.TemporaryDirectory() as directory:
            script = Path(directory) / 'policy.groovy'
            script.write_text(code, encoding='utf-8')
            result = subprocess.run([str(java), '-cp', str(lib / '*'), 'groovy.ui.GroovyMain', str(script), str(repo / 'android/app/parser-qa-abi.gradle')], capture_output=True, timeout=20)
        self.assertEqual(result.returncode, 0, result.stderr.decode('utf-8', 'replace'))
        self.assertIn(b'qa_actual_groovy_policy_matrix_and_negative_pass', result.stdout)


if __name__ == '__main__':
    unittest.main()
