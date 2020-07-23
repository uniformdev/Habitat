module.exports = function () {
  var instanceRoot = process.env.INSTANCE_ROOT;
  if (!instanceRoot) throw 'INSTANCE_ROOT env var is not defined' 

  var config = {
    websiteRoot: instanceRoot + "\\",
    sitecoreLibraries: instanceRoot + "\\bin",
    licensePath: instanceRoot + "\\App_Data\\license.xml",
    packageXmlBasePath: ".\\src\\Project\\Habitat\\code\\App_Data\\packages\\habitat.xml",
    packagePath: instanceRoot + "\\App_Data\\packages",
    solutionName: "Habitat",
    buildConfiguration: "Debug",
    buildToolsVersion: '16.0',
    buildMaxCpuCount: 0,
    buildVerbosity: "minimal",
    buildPlatform: "Any CPU",
    publishPlatform: "AnyCpu",
    runCleanBuilds: false
  };
  return config;
}
