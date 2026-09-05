output "name" {
  description = "Generated resource name using whichever pattern (standard or compact) applies to resource_type. This is the output resource modules should use."
  value       = local.name

  precondition {
    condition     = local.resource_type_valid
    error_message = "Unknown resource_type \"${var.resource_type}\". Valid values: ${join(", ", keys(local.resource_types))}."
  }

  precondition {
    condition     = local.region_valid
    error_message = "Unknown region \"${var.region}\". Valid values: ${join(", ", keys(local.region_abbreviations))}."
  }

  precondition {
    condition     = local.resource_type_info.scheme != "compact" || try(local.resource_type_info.max_length, null) == null || length(local.compact_name_raw) <= local.compact_max_length
    error_message = "Compact name \"${local.compact_name_raw}\" (${length(local.compact_name_raw)} chars) exceeds the ${try(local.resource_type_info.max_length, "n/a")}-char limit for resource_type \"${var.resource_type}\". Shorten workload/instance rather than relying on truncation."
  }
}

output "standard_name" {
  description = "Name in CAF's standard hyphenated pattern, regardless of the resource type's canonical scheme."
  value       = local.standard_name
}

output "compact_name" {
  description = "Name in CAF's compact (no-hyphen, lowercase) pattern, truncated to the resource type's max_length if one is set."
  value       = local.compact_name
}
