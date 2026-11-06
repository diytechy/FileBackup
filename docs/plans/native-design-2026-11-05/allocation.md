# Draft allocation and legacy comparison map

This is proposed allocation, not implementation coverage or approval. All new rows
are Drafted. Symbols name logical responsibilities; no Rust source exists for them.
Every accepted SR has a planned design and case, but a reference alone does not
demonstrate semantic completeness. See the [review guide](review.md).

## New design and verification inventory

| Design | Responsibility | Parent SRs | Planned cases |
|---|---|---|---|
| LLR-151 | Whole-configuration admission | SR-018, SR-042, SR-123, SR-134, SR-135, SR-129 | TC-261 |
| LLR-152 | Resolved root and view ownership admission | SR-063, SR-138, SR-154 | TC-262 |
| LLR-153 | Independent action dispatch and aggregate results | SR-014, SR-043, SR-095, SR-142 | TC-263 |
| LLR-154 | Required and optional dependency admission | SR-016, SR-019, SR-118, SR-132, SR-133 | TC-264 |
| LLR-155 | Supported ownership acquisition and release | SR-085, SR-086, SR-107 | TC-265 |
| LLR-156 | Source walk and declared exclusions | SR-001, SR-074, SR-088, SR-089, SR-093, SR-094 | TC-266 |
| LLR-157 | Portable names and collision groups | SR-021, SR-055, SR-092 | TC-267 |
| LLR-158 | Metadata reuse and deterministic rereads | SR-011, SR-024, SR-105, SR-005, SR-100 | TC-268 |
| LLR-159 | Streaming capture and source-change detection | SR-003, SR-053, SR-059, SR-108 | TC-269 |
| LLR-160 | Bounded retry scheduling and frozen prior rows | SR-067, SR-090, SR-091 | TC-270 |
| LLR-161 | Missing and empty source stop semantics | SR-036, SR-091 | TC-271 |
| LLR-162 | Compression decision and immutable mixed forms | SR-081, SR-096, SR-111 | TC-272 |
| LLR-163 | Existing content-addressed pool and immutable publication | SR-003, SR-041, SR-059, SR-108, SR-136 | TC-273 |
| LLR-164 | Versioned file and directory/link record codecs | SR-039, SR-065, SR-066, SR-146, SR-150, SR-152 | TC-274 |
| LLR-165 | Existing bounded publication with explicit metadata failure handling | SR-005, SR-010, SR-017, SR-075, SR-082, SR-100 | TC-275 |
| LLR-166 | Interruption cleanup and durability boundary | SR-017, SR-075, SR-082, SR-158 | TC-276 |
| LLR-167 | Capacity estimates and late write failures | SR-023, SR-052, SR-158 | TC-277 |
| LLR-168 | Read-only inventory and whole-store verification | SR-047, SR-049, SR-103, SR-104 | TC-278 |
| LLR-169 | Existing retention plan and resumable removal | SR-045, SR-046, SR-047, SR-101, SR-102 | TC-279 |
| LLR-170 | Protected dependency checks for snapshot deletion | SR-045, SR-046, SR-059, SR-101 | TC-280 |
| LLR-171 | Verified repair without invented history | SR-109, SR-110 | TC-281 |
| LLR-172 | Recovery selection and admission | SR-008, SR-009, SR-010, SR-031, SR-039, SR-118, SR-141, SR-145 | TC-282 |
| LLR-173 | Per-file verified recovery and fallback | SR-029, SR-056, SR-068, SR-119, SR-120 | TC-283 |
| LLR-174 | Restore path containment and collision admission | SR-009, SR-092, SR-121, SR-141 | TC-284 |
| LLR-175 | Folder and per-file metadata restoration | SR-065, SR-066, SR-122, SR-146 | TC-285 |
| LLR-176 | Capture and reconstruct portable folder links | SR-150, SR-151, SR-152 | TC-286 |
| LLR-177 | External-link capture scope and finite traversal | SR-001, SR-137, SR-150, SR-151 | TC-287 |
| LLR-178 | Stable result classes and structured diagnostics | SR-040, SR-043, SR-104, SR-120, SR-126 | TC-288 |
| LLR-179 | Unattended execution and interactive recovery | SR-016, SR-072, SR-073 | TC-289 |
| LLR-180 | Progress, change accounting and refusal explanations | SR-089, SR-124, SR-125, SR-126 | TC-290 |
| LLR-181 | Notification and credential isolation | SR-015, SR-127, SR-128, SR-129 | TC-291 |
| LLR-182 | Derived browse and space/media views | SR-062, SR-063, SR-097, SR-098, SR-099, SR-147 | TC-292 |
| LLR-183 | Container execution parity and confinement | SR-034, SR-048, SR-095, SR-130, SR-142 | TC-293 |
| LLR-184 | Native builds and independent script recovery packaging | SR-007, SR-008, SR-031, SR-033, SR-153 | TC-294 |
| LLR-185 | Format support and explicit transition paths | SR-061, SR-084, SR-114, SR-115, SR-116, SR-123, SR-156 | TC-295 |
| LLR-186 | Interrupted kit refresh with a usable prior route | SR-007, SR-084, SR-110, SR-117 | TC-296 |
| LLR-187 | Stored-form detection and optional tool adapters | SR-068, SR-071, SR-081, SR-098, SR-118 | TC-297 |
| LLR-188 | Resource-bounded indexes and streaming records | SR-049, SR-064, SR-112, SR-113 | TC-298 |
| LLR-189 | Scale corpus and reproducible performance measurements | SR-064, SR-112, SR-113 | TC-299 |
| LLR-190 | Guidance, helper and assurance disclosures | SR-027, SR-126, SR-131, SR-143, SR-155, SR-156, SR-157 | TC-300, TC-301 |

## Parent coverage

| Accepted SR | Planned design |
|---|---|
| SR-001 | LLR-156, LLR-177 |
| SR-003 | LLR-159, LLR-163 |
| SR-005 | LLR-158, LLR-165 |
| SR-007 | LLR-184, LLR-186 |
| SR-008 | LLR-172, LLR-184 |
| SR-009 | LLR-172, LLR-174 |
| SR-010 | LLR-165, LLR-172 |
| SR-011 | LLR-158 |
| SR-014 | LLR-153 |
| SR-015 | LLR-181 |
| SR-016 | LLR-154, LLR-179 |
| SR-017 | LLR-165, LLR-166 |
| SR-018 | LLR-151 |
| SR-019 | LLR-154 |
| SR-021 | LLR-157 |
| SR-023 | LLR-167 |
| SR-024 | LLR-158 |
| SR-027 | LLR-190 |
| SR-029 | LLR-173 |
| SR-031 | LLR-172, LLR-184 |
| SR-033 | LLR-184 |
| SR-034 | LLR-183 |
| SR-036 | LLR-161 |
| SR-039 | LLR-164, LLR-172 |
| SR-040 | LLR-178 |
| SR-041 | LLR-163 |
| SR-042 | LLR-151 |
| SR-043 | LLR-153, LLR-178 |
| SR-045 | LLR-169, LLR-170 |
| SR-046 | LLR-169, LLR-170 |
| SR-047 | LLR-168, LLR-169 |
| SR-048 | LLR-183 |
| SR-049 | LLR-168, LLR-188 |
| SR-052 | LLR-167 |
| SR-053 | LLR-159 |
| SR-055 | LLR-157 |
| SR-056 | LLR-173 |
| SR-059 | LLR-159, LLR-163, LLR-170 |
| SR-061 | LLR-185 |
| SR-062 | LLR-182 |
| SR-063 | LLR-152, LLR-182 |
| SR-064 | LLR-188, LLR-189 |
| SR-065 | LLR-164, LLR-175 |
| SR-066 | LLR-164, LLR-175 |
| SR-067 | LLR-160 |
| SR-068 | LLR-173, LLR-187 |
| SR-071 | LLR-187 |
| SR-072 | LLR-179 |
| SR-073 | LLR-179 |
| SR-074 | LLR-156 |
| SR-075 | LLR-165, LLR-166 |
| SR-081 | LLR-162, LLR-187 |
| SR-082 | LLR-165, LLR-166 |
| SR-084 | LLR-185, LLR-186 |
| SR-085 | LLR-155 |
| SR-086 | LLR-155 |
| SR-088 | LLR-156 |
| SR-089 | LLR-156, LLR-180 |
| SR-090 | LLR-160 |
| SR-091 | LLR-160, LLR-161 |
| SR-092 | LLR-157, LLR-174 |
| SR-093 | LLR-156 |
| SR-094 | LLR-156 |
| SR-095 | LLR-153, LLR-183 |
| SR-096 | LLR-162 |
| SR-097 | LLR-182 |
| SR-098 | LLR-182, LLR-187 |
| SR-099 | LLR-182 |
| SR-100 | LLR-158, LLR-165 |
| SR-101 | LLR-169, LLR-170 |
| SR-102 | LLR-169 |
| SR-103 | LLR-168 |
| SR-104 | LLR-168, LLR-178 |
| SR-105 | LLR-158 |
| SR-107 | LLR-155 |
| SR-108 | LLR-159, LLR-163 |
| SR-109 | LLR-171 |
| SR-110 | LLR-171, LLR-186 |
| SR-111 | LLR-162 |
| SR-112 | LLR-188, LLR-189 |
| SR-113 | LLR-188, LLR-189 |
| SR-114 | LLR-185 |
| SR-115 | LLR-185 |
| SR-116 | LLR-185 |
| SR-117 | LLR-186 |
| SR-118 | LLR-154, LLR-172, LLR-187 |
| SR-119 | LLR-173 |
| SR-120 | LLR-173, LLR-178 |
| SR-121 | LLR-174 |
| SR-122 | LLR-175 |
| SR-123 | LLR-151, LLR-185 |
| SR-124 | LLR-180 |
| SR-125 | LLR-180 |
| SR-126 | LLR-178, LLR-180, LLR-190 |
| SR-127 | LLR-181 |
| SR-128 | LLR-181 |
| SR-129 | LLR-151, LLR-181 |
| SR-130 | LLR-183 |
| SR-131 | LLR-190 |
| SR-132 | LLR-154 |
| SR-133 | LLR-154 |
| SR-134 | LLR-151 |
| SR-135 | LLR-151 |
| SR-136 | LLR-163 |
| SR-137 | LLR-177 |
| SR-138 | LLR-152 |
| SR-141 | LLR-172, LLR-174 |
| SR-142 | LLR-153, LLR-183 |
| SR-143 | LLR-190 |
| SR-145 | LLR-172 |
| SR-146 | LLR-164, LLR-175 |
| SR-147 | LLR-182 |
| SR-150 | LLR-164, LLR-176, LLR-177 |
| SR-151 | LLR-176, LLR-177 |
| SR-152 | LLR-164, LLR-176 |
| SR-153 | LLR-184 |
| SR-154 | LLR-152 |
| SR-155 | LLR-190 |
| SR-156 | LLR-185, LLR-190 |
| SR-157 | LLR-190 |
| SR-158 | LLR-166, LLR-167 |

## Retired legacy design crosswalk

The [cleanup decision](legacy-cleanup.md) retires the 87 imported LLRs and 240
test definitions from the active baseline. Their original status/evidence remains
in the spine resync harvest and git; executable tests remain migration inputs.
The [earlier code attachment audit](../spine-rebaseline-2026-11-05/code-attachment-audit.md)
is historical navigation, not proof against the revised SRs. Read the actual
code, rationale and assertions before reusing them in a native work package.

The following candidates share a *current SR reference* with a retired design.
That intersection is not equivalence. A dash means no shared current parent,
not that every behavior in the old row was invalid. Hash/name/CSV fixture details,
for example, remain inputs to N1 even where parent IDs changed.

| Legacy design | Candidate new designs by shared parent |
|---|---|
| [LLR-001](../../log.d/retired/LLR-001.md) | LLR-156, LLR-177 |
| [LLR-002](../../log.d/retired/LLR-002.md) | — |
| [LLR-003](../../log.d/retired/LLR-003.md) | LLR-159, LLR-163 |
| [LLR-004](../../log.d/retired/LLR-004.md) | — |
| [LLR-005](../../log.d/retired/LLR-005.md) | LLR-158, LLR-165 |
| [LLR-006](../../log.d/retired/LLR-006.md) | — |
| [LLR-007](../../log.d/retired/LLR-007.md) | LLR-184, LLR-186 |
| [LLR-008](../../log.d/retired/LLR-008.md) | LLR-172, LLR-184 |
| [LLR-009](../../log.d/retired/LLR-009.md) | LLR-172, LLR-174 |
| [LLR-010](../../log.d/retired/LLR-010.md) | LLR-165, LLR-172 |
| [LLR-011](../../log.d/retired/LLR-011.md) | LLR-158 |
| [LLR-014](../../log.d/retired/LLR-014.md) | LLR-153 |
| [LLR-015](../../log.d/retired/LLR-015.md) | LLR-181 |
| [LLR-016](../../log.d/retired/LLR-016.md) | LLR-154, LLR-179 |
| [LLR-017](../../log.d/retired/LLR-017.md) | LLR-165, LLR-166 |
| [LLR-018](../../log.d/retired/LLR-018.md) | LLR-151 |
| [LLR-020](../../log.d/retired/LLR-020.md) | — |
| [LLR-021](../../log.d/retired/LLR-021.md) | LLR-157 |
| [LLR-022](../../log.d/retired/LLR-022.md) | — |
| [LLR-023](../../log.d/retired/LLR-023.md) | LLR-167 |
| [LLR-024](../../log.d/retired/LLR-024.md) | LLR-158 |
| [LLR-025](../../log.d/retired/LLR-025.md) | — |
| [LLR-026](../../log.d/retired/LLR-026.md) | — |
| [LLR-028](../../log.d/retired/LLR-028.md) | — |
| [LLR-027](../../log.d/retired/LLR-027.md) | LLR-190 |
| [LLR-029](../../log.d/retired/LLR-029.md) | LLR-173 |
| [LLR-030](../../log.d/retired/LLR-030.md) | — |
| [LLR-031](../../log.d/retired/LLR-031.md) | LLR-172, LLR-184 |
| [LLR-032](../../log.d/retired/LLR-032.md) | — |
| [LLR-033](../../log.d/retired/LLR-033.md) | LLR-184 |
| [LLR-035](../../log.d/retired/LLR-035.md) | — |
| [LLR-036](../../log.d/retired/LLR-036.md) | LLR-161 |
| [LLR-037](../../log.d/retired/LLR-037.md) | — |
| [LLR-038](../../log.d/retired/LLR-038.md) | — |
| [LLR-039](../../log.d/retired/LLR-039.md) | LLR-164, LLR-172 |
| [LLR-040](../../log.d/retired/LLR-040.md) | LLR-178 |
| [LLR-041](../../log.d/retired/LLR-041.md) | LLR-163 |
| [LLR-042](../../log.d/retired/LLR-042.md) | LLR-151 |
| [LLR-043](../../log.d/retired/LLR-043.md) | LLR-153, LLR-178 |
| [LLR-045](../../log.d/retired/LLR-045.md) | LLR-169, LLR-170 |
| [LLR-046](../../log.d/retired/LLR-046.md) | LLR-164, LLR-169, LLR-170, LLR-172 |
| [LLR-047](../../log.d/retired/LLR-047.md) | LLR-168, LLR-169, LLR-170 |
| [LLR-048](../../log.d/retired/LLR-048.md) | LLR-153, LLR-178, LLR-183 |
| [LLR-049](../../log.d/retired/LLR-049.md) | LLR-168, LLR-178, LLR-188 |
| [LLR-050](../../log.d/retired/LLR-050.md) | LLR-173, LLR-178 |
| [LLR-051](../../log.d/retired/LLR-051.md) | LLR-159, LLR-163, LLR-170 |
| [LLR-052](../../log.d/retired/LLR-052.md) | LLR-153, LLR-167, LLR-178 |
| [LLR-053](../../log.d/retired/LLR-053.md) | LLR-159 |
| [LLR-054](../../log.d/retired/LLR-054.md) | LLR-169, LLR-170 |
| [LLR-055](../../log.d/retired/LLR-055.md) | LLR-157 |
| [LLR-056](../../log.d/retired/LLR-056.md) | LLR-173 |
| [LLR-057](../../log.d/retired/LLR-057.md) | — |
| [LLR-058](../../log.d/retired/LLR-058.md) | LLR-159, LLR-163 |
| [LLR-059](../../log.d/retired/LLR-059.md) | LLR-159, LLR-163, LLR-165, LLR-170, LLR-172 |
| [LLR-060](../../log.d/retired/LLR-060.md) | LLR-185 |
| [LLR-061](../../log.d/retired/LLR-061.md) | LLR-182 |
| [LLR-062](../../log.d/retired/LLR-062.md) | LLR-188, LLR-189 |
| [LLR-063](../../log.d/retired/LLR-063.md) | LLR-151, LLR-152, LLR-182 |
| [LLR-064](../../log.d/retired/LLR-064.md) | LLR-182 |
| [LLR-065](../../log.d/retired/LLR-065.md) | LLR-164, LLR-175 |
| [LLR-066](../../log.d/retired/LLR-066.md) | LLR-164, LLR-175 |
| [LLR-067](../../log.d/retired/LLR-067.md) | LLR-160 |
| [LLR-068](../../log.d/retired/LLR-068.md) | LLR-173, LLR-187 |
| [LLR-069](../../log.d/retired/LLR-069.md) | LLR-185 |
| [LLR-070](../../log.d/retired/LLR-070.md) | — |
| [LLR-071](../../log.d/retired/LLR-071.md) | LLR-187 |
| [LLR-072](../../log.d/retired/LLR-072.md) | LLR-172, LLR-174, LLR-187 |
| [LLR-073](../../log.d/retired/LLR-073.md) | LLR-154, LLR-179 |
| [LLR-074](../../log.d/retired/LLR-074.md) | LLR-179 |
| [LLR-075](../../log.d/retired/LLR-075.md) | LLR-184, LLR-186 |
| [LLR-076](../../log.d/retired/LLR-076.md) | LLR-168, LLR-184, LLR-186, LLR-188 |
| [LLR-077](../../log.d/retired/LLR-077.md) | LLR-184, LLR-186 |
| [LLR-078](../../log.d/retired/LLR-078.md) | LLR-156 |
| [LLR-079](../../log.d/retired/LLR-079.md) | LLR-172, LLR-174 |
| [LLR-080](../../log.d/retired/LLR-080.md) | LLR-165, LLR-166 |
| [LLR-086](../../log.d/retired/LLR-086.md) | LLR-162, LLR-187 |
| [LLR-087](../../log.d/retired/LLR-087.md) | LLR-165, LLR-166 |
| [LLR-088](../../log.d/retired/LLR-088.md) | LLR-165, LLR-166 |
| [LLR-090](../../log.d/retired/LLR-090.md) | LLR-155 |
| [LLR-091](../../log.d/retired/LLR-091.md) | LLR-155, LLR-165, LLR-166 |
| [LLR-092](../../log.d/retired/LLR-092.md) | LLR-155, LLR-169, LLR-170 |
| [LLR-093](../../log.d/retired/LLR-093.md) | LLR-155 |
| [LLR-094](../../log.d/retired/LLR-094.md) | LLR-155 |
| [LLR-095](../../log.d/retired/LLR-095.md) | LLR-151, LLR-152, LLR-153, LLR-182 |
| [LLR-096](../../log.d/retired/LLR-096.md) | LLR-159, LLR-163 |
| [LLR-097](../../log.d/retired/LLR-097.md) | LLR-156, LLR-157, LLR-164, LLR-175, LLR-177 |
| [LLR-098](../../log.d/retired/LLR-098.md) | LLR-165, LLR-172, LLR-174, LLR-184, LLR-186 |
