locals {
  # Microsoft CAF recommended abbreviations.
  # scheme "standard" -> <abbr>-<workload>-<environment>-<region>-<instance>
  # scheme "compact"  -> <abbr><workload><environment><region><instance>, lowercase, no hyphens
  # Keep in sync with policy/naming.rego's resource_types table.
  resource_types = {
    resource_group         = { abbr = "rg", scheme = "standard" }
    virtual_network        = { abbr = "vnet", scheme = "standard" }
    subnet                 = { abbr = "snet", scheme = "standard" }
    network_security_group = { abbr = "nsg", scheme = "standard" }
    public_ip              = { abbr = "pip", scheme = "standard" }
    route_table            = { abbr = "rt", scheme = "standard" }
    storage_account        = { abbr = "st", scheme = "compact", max_length = 24 }
    key_vault              = { abbr = "kv", scheme = "compact", max_length = 24 }
  }

  # Azure public-cloud US regions.
  region_abbreviations = {
    eastus         = "eus"
    eastus2        = "eus2"
    centralus      = "cus"
    northcentralus = "ncus"
    southcentralus = "scus"
    westcentralus  = "wcus"
    westus         = "wus"
    westus2        = "wus2"
    westus3        = "wus3"
  }

  resource_type_valid = contains(keys(local.resource_types), var.resource_type)
  region_valid        = contains(keys(local.region_abbreviations), var.region)

  # Safe fallbacks so locals never error out before the output preconditions
  # get a chance to report a clean message.
  resource_type_info = local.resource_type_valid ? local.resource_types[var.resource_type] : { abbr = "invalid", scheme = "standard" }
  region_abbr        = local.region_valid ? local.region_abbreviations[var.region] : "invalid"

  standard_name = join("-", [local.resource_type_info.abbr, var.workload, var.environment, local.region_abbr, var.instance])

  compact_name_raw   = lower(join("", [local.resource_type_info.abbr, var.workload, var.environment, local.region_abbr, var.instance]))
  compact_max_length = try(local.resource_type_info.max_length, length(local.compact_name_raw))
  compact_name       = substr(local.compact_name_raw, 0, local.compact_max_length)

  name = local.resource_type_info.scheme == "compact" ? local.compact_name : local.standard_name
}
