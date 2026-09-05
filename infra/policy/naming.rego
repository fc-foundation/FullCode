package main

import future.keywords.in

# Keep this table in sync with terraform/modules/naming/locals.tf's resource_types map.
resource_types := {
	"resource_group": {"abbr": "rg", "scheme": "standard"},
	"virtual_network": {"abbr": "vnet", "scheme": "standard"},
	"subnet": {"abbr": "snet", "scheme": "standard"},
	"network_security_group": {"abbr": "nsg", "scheme": "standard"},
	"public_ip": {"abbr": "pip", "scheme": "standard"},
	"route_table": {"abbr": "rt", "scheme": "standard"},
	"storage_account": {"abbr": "st", "scheme": "compact"},
	"key_vault": {"abbr": "kv", "scheme": "compact"},
}

standard_pattern(abbr) := sprintf("^%s-fc-(dev|test|prod)-(eus2)-[0-9]{3}$", [abbr])

compact_pattern(abbr) := sprintf("^%sfc(dev|test|prod)(eus2)[0-9]{3}$", [abbr])

name_matches(info, name) {
	info.scheme == "standard"
	regex.match(standard_pattern(info.abbr), name)
}

name_matches(info, name) {
	info.scheme == "compact"
	regex.match(compact_pattern(info.abbr), name)
}

# --- Rule set 1: naming-module self-test (works today, no cloud credentials).
# terraform/examples/naming-check exports every resource_type -> generated name.
deny[msg] {
	some resource_type, name in input.planned_values.outputs.generated_names.value
	info := resource_types[resource_type]
	not name_matches(info, name)
	msg := sprintf("naming: %q generated %q which does not match the %s pattern", [resource_type, name, info.scheme])
}

deny[msg] {
	some resource_type, _ in input.planned_values.outputs.generated_names.value
	not resource_types[resource_type]
	msg := sprintf("naming: unknown resource_type %q — add it to policy/naming.rego and modules/naming/locals.tf", [resource_type])
}

# --- Rule set 2: real resource plans (future — once environment roots with
# azurerm_* resources exist). Maps Terraform resource type -> naming key.
tf_type_to_key := {
	"azurerm_resource_group": "resource_group",
	"azurerm_virtual_network": "virtual_network",
	"azurerm_subnet": "subnet",
	"azurerm_network_security_group": "network_security_group",
	"azurerm_public_ip": "public_ip",
	"azurerm_route_table": "route_table",
	"azurerm_storage_account": "storage_account",
	"azurerm_key_vault": "key_vault",
}

deny[msg] {
	some rc in input.resource_changes
	key := tf_type_to_key[rc.type]
	info := resource_types[key]
	name := rc.change.after.name
	not name_matches(info, name)
	msg := sprintf("naming: %s.%s -> %q does not match the %s pattern", [rc.type, rc.name, name, info.scheme])
}
