namespace Sitecore.Feature.Multisite.Models
{
  using Sitecore.Text;

  public class SiteConfiguration
  {
    public string Name { get; set; }
    public string Title { get; set; }
    public bool IsCurrent { get; set; }

    public string Url { get; set; }

    public bool ShowInMenu { get; set; }
  }
}