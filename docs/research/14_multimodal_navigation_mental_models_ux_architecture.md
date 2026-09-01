# User-Proven Table Stakes, Cognitive Mental Models, and System Design Architecture for Multimodal Urban Navigation

The modern urban transport landscape requires navigation interfaces that seamlessly synthesize disparate transit modes—scheduled public transit, micro-mobility, bike-share systems, and walking—into a unified, low-friction experience. Designing such platforms requires addressing fundamental challenges in human spatial cognition, emotional friction, and real-time data interpretation. When navigating complex urban environments, users make rapid decisions under cognitive load, spatial anxiety, and severe time constraints.

This research specification establishes the user-proven baseline features, behavioral mental models, competitive UX benchmarks, and system architecture recommendations necessary to build an expert-level multimodal navigation platform for Dérivée.

---

## Executive Deliverables

### 1. User Pain Point Taxonomy

Urban navigation failure modes induce distinct emotional and cognitive stresses across the trip lifecycle. The table below presents a prioritized breakdown of the top ten acute user friction points across **Pre-Trip Planning**, **Active In-Transit**, and **Transfer/Arrival** phases.

| Trip Phase | Acute Friction Point | Cognitive & Emotional Impact | Root Cause / System Failure | Mitigating UX Pattern & System Behavior |
|:---|:---|:---|:---|:---|
| **Pre-Trip** | **Ghost Vehicle Anxiety** | Severe trust breakdown; decision paralysis; fear of stranded waiting. | GTFS-RT feed drops, uncommunicated cancellations, or stale vehicle-to-block assignments. | Tiered confidence badges (Verified / Estimated / Static), dynamic vehicle GPS dots, and ETA completeness scoring. |
| **Pre-Trip** | **Micro-Mobility Hardware Blindness** | Frustration at origin; wasted physical effort walking to unserviceable vehicles. | Lack of real-time GBFS e-bike battery percentage, range estimation, or damage reports. | Vehicle state-of-charge overlays, usable range radiuses, and physical condition tags. |
| **Pre-Trip** | **Alert Banner Fatigue** | Visual overload; ignore critical alerts due to irrelevance. | Generic system-wide agency banners pushed indiscriminately to all users. | Context-aware, inline journey impact alerts filtered exclusively to active itinerary lines. |
| **Active** | **Subterranean Orientation Loss** | Acute disorientation; panic during tight underground transfers. | GPS signal loss ("urban canyon" and subterranean multipath errors) inside deep hubs. | Pre-rendered indoor vector maps, step-by-step schematic guides, and deterministic exit numbering (e.g., "Exit 4B"). |
| **Active** | **Turn-by-Turn Cognitive Fatigue** | Screen fixation; degraded spatial awareness; heightened safety risk. | Over-reliance on numerical distances ("turn in 300ft") rather than human anchors. | Landmark-based decision-point cues ("Turn left after the red brick pharmacy"). |
| **Active** | **High Traffic Stress Exposure** | Physical danger; elevated anxiety; detour abandonment. | Routing engines prioritizing raw travel speed over protected cycle infrastructure. | Level of Traffic Stress (LTS) routing filters prioritizing physically separated paths. |
| **Active** | **Thermal Exposure & Heat Stress** | Severe discomfort; physical exhaustion; route abandonment in summer. | Ignoring microclimate variables like solar radiation, shade, and surface temperature. | Shaded path routing leveraging urban tree canopy cover and building shadow vectors ($\text{PET}$ cost minimization). |
| **Transfer** | **Destination Dock Exhaustion** | Anxiety near destination; unexpected walking distance; overtime charges. | GBFS destination docks filling up while the user is actively riding. | Predictive dock availability gating, auto-reservation buffers, and dynamic overflow rerouting. |
| **Transfer** | **Layover Dwell & Sprint Risk** | Fatigue from long platform waits or missed connections due to tight layovers. | Fixed walking speed assumptions ignoring vertical transfer times and headways. | "Smart Departures" with personalized walking speeds, headway-adaptive transfer slack, and dwell optimization. |
| **Transfer** | **Subway Platform Misalignment** | Long walking distances at destination; missed tight transfers. | Missing train car positioning data relative to station exits and transfers. | Platform train car recommendation badges (e.g., "Board near front/middle car"). |

---

### 2. Table Stakes Feature Matrix

To avoid feature bloat while guaranteeing core utility, platform capabilities are classified into **Mandatory Baseline (Table Stakes)**, **Delighters/Differentiators**, and **Anti-Patterns/Clutter**.

| Feature Category | Feature Description & Functional Scope | Target Mental Model / UX Impact |
|:---|:---|:---|
| **Mandatory Baseline (Table Stakes)** | Live GTFS-RT countdowns with data confidence indicators. | Resolves arrival anxiety and establishes basic platform reliability. |
| **Mandatory Baseline (Table Stakes)** | Real-time GBFS bike and dock inventory counts. | Prevents wasted trips to empty stations or full docks. |
| **Mandatory Baseline (Table Stakes)** | Multimodal turn-by-turn routing (transit, walking, micro-mobility). | Provides seamless A-to-B navigation across modes. |
| **Mandatory Baseline (Table Stakes)** | Clear cost, total distance, and time summaries per mode. | Enables informed travel trade-offs before departure. |
| **Mandatory Baseline (Table Stakes)** | Step-free accessibility filter options. | Essential for passengers with mobility devices or strollers. |
| **Mandatory Baseline (Table Stakes)** | Mobile OS Lock Screen & Live Activity integration. | Delivers passive, glanceable progress tracking on the go. |
| **Delighters & Differentiators** | Platform car exit positioning (Front / Middle / Back). | Empowers power commuters to optimize transfer times. |
| **Delighters & Differentiators** | Microclimate shaded walking path routing. | Maximizes thermal comfort during high heat events. |
| **Delighters & Differentiators** | "Smart Departures" & transfer slack optimization. | Prevents unnecessary platform dwell time and sprint risk. |
| **Delighters & Differentiators** | Subterranean exit mapping (Exit 4B, elevators). | Eliminates underground exit disorientation. |
| **Delighters & Differentiators** | Predictive dock availability and dynamic rerouting. | Guarantees destination dock availability mid-ride. |
| **Delighters & Differentiators** | Context-aware, inline journey impact disruption alerts. | Surfaces relevant warnings without alert fatigue. |
| **Anti-Patterns & Clutter** | Full-screen generic agency alert pop-ups. | Causes cognitive friction and alert fatigue. |
| **Anti-Patterns & Clutter** | Numerical distance-only walking instructions ("in 300ft"). | Increases screen fixation and disorientation. |
| **Anti-Patterns & Clutter** | Automatic map re-centering during active user pan/zoom. | Interrupts spatial exploration and user control. |
| **Anti-Patterns & Clutter** | Unfiltered micro-mobility network overlay clutter. | Obscures main transit polylines with irrelevant markers. |
| **Anti-Patterns & Clutter** | Manual pull-to-refresh requirements for ETAs. | Forces unnecessary manual interaction for live updates. |
| **Anti-Patterns & Clutter** | Flat chronological arrival lists for complex multi-branch rail. | Hinders rapid comparison across express and local branches. |

---

### 3. Competitive Heuristic Benchmark

Leading mobility platforms deploy distinct interaction models and architectural choices. The benchmark table below evaluates seven major platforms across strengths, weaknesses, and key structural takeaways.

| Platform | Core UX Strengths & Validated Patterns | Critical Weaknesses & Vulnerabilities | Key Design Takeaway |
|:---|:---|:---|:---|
| **Citymapper** | Granular subway exit mapping, car positioning badges, and unified multimodal leg chaining. | Advanced features locked behind regional paywalls; visual map clutter in dense cores. | Adopt platform car exit indicators and subterranean transfer schematics. |
| **Transit App** | High-contrast departure boards anchored to map; crowdsourced vehicle tracking ("GO"). | Geographical paywalling of features; departure list sheet can block map exploration. | Emulate crowdsourced vehicle validation to bridge agency feed gaps; keep map visible. |
| **Google Maps** | Comprehensive global POI database; smooth transitions between indoor and outdoor mapping. | Poor landmark integration in walking mode; micro-mobility leg chaining feels secondary. | Avoid distance-only turn directions; enhance native micro-mobility integration. |
| **Apple Maps** | Best-in-class iOS Lock Screen and Dynamic Island trip tracking; clean visual hierarchy. | Transit line overlays can obscure complex high-density networks; limited micro-mobility depth. | Adopt native iOS Live Activity structures and Dynamic Island views. |
| **Naver Maps / KakaoMap** | Grid/matrix timetable views for complex multi-branch rail; accurate local platform exit data. | Text-heavy UI creates steep learning curve for visitors; relies on local language fluency. | Utilize matrix grid views for high-density, multi-branch rail corridors. |
| **Jorudan / Tokyo Metro** | Masterful visual representation of local vs. express train splits; deterministic grid timetables. | Dated visual design; steep learning curve; minimal micro-mobility integration. | Learn from Japanese express/local visual hierarchy and timetable matrices. |
| **Strava** | Surface quality mapping, safety heatmaps, and granular elevation profile visualization. | Athletic focus lacks public transit trip-planning capabilities entirely. | Adapt surface quality and safety metadata for utility cycling engines. |

---

### 4. Multimodal User Persona Profiles

User behavior varies widely based on physical capabilities, temporal constraints, risk tolerance, and modal preferences. The target profiles below highlight these contrasting behavioral models.

| Persona Dimension | Profile 1: Elena Vance | Profile 2: Marcus Chen | Profile 3: Dr. Arthur Pendelton |
|:---|:---|:---|:---|
| **Role & Persona Type** | *"The Time-Critical Power Commuter"* | *"The Low-Stress Comfort Cyclist"* | *"The Accessible Ambient Pedestrian"* |
| **Demographics** | Age 34 \| Suburb-to-Core Rail Rider | Age 29 \| Urban Resident & Rider | Age 68 \| Urban Explorer & Walker |
| **Primary Goal** | Minimize total travel time with zero platform dwell time. | Predictable, safe, and stress-free bike commute. | Comfortable, accessible, and cognitive-friendly walking. |
| **Modal Preferences** | Express Rail, Subway, Fast Walk. | Shared E-Bikes, Protected Lanes. | Low-floor Bus, Elevator Rail, Shaded Walk. |
| **Physical Tolerance** | High pace; willingly sprints for connections. | Moderate exertion; avoids steep hills. | Low pace; requires flat, shaded paths. |
| **Risk Tolerance** | Zero tolerance for unannounced delays. | Low tolerance for shared auto traffic. | Low tolerance for complex transfers. |
| **Core UI Needs** | Train car exit badges, inline disruption alerts, Live Activities. | Protected bike route filters, GBFS battery/dock indicators, high-contrast UI. | Step-free route filters, visual landmark directions, high-contrast text. |

---

## Technical Investigation & Cognitive Deep-Dives

### 1. Public Transit Commuter Psychology & Table Stakes

#### Arrival Reliability & Headway Mental Models

Public transit riders process arrival schedules through three main mental frames:
1. **Published static timetables** (clock-time scheduled departures).
2. **Relative countdown timers** ("in 4 mins").
3. **Headway frequency intervals** ("trains every 3–5 mins").

In urban corridors where service headways fall below 6 minutes, user reliance on published static timetables drops significantly. Passengers transition from schedule-driven departure planning to arrival-interval planning. Displaying static clock times (e.g., "08:42 AM") in high-frequency environments introduces unnecessary mental arithmetic, whereas relative countdowns directly answer the user's primary mental question: *"How long must I stand on this platform?"*.

```
   HIGH HEADWAY (>15 min)                 LOW HEADWAY (<6 min)
┌───────────────────────────┐         ┌───────────────────────────┐
│ Schedule-Driven Planning  │         │  Arrival-Interval Logic   │
│ Clock Time: "Arrives 8:42"│         │  Relative: "In 3 mins"    │
│ Strict Departure Gating   │         │  Headway: "Every 4 mins"  │
└───────────────────────────┘         └───────────────────────────┘
```

The **"ghost bus" phenomenon**—where real-time feeds count down to 0 minutes but no vehicle arrives—is a major cause of user abandonment. Ghost buses stem from GTFS-Realtime (GTFS-RT) data errors, including dropped Automatic Vehicle Location (AVL) GPS signals, uncommunicated trip cancellations, or broken vehicle-to-block assignments.

To eliminate ghost vehicles, modern systems track an **ETA Completeness Benchmark**, defined as the percentage of complete, real-time communicated trip-stops relative to scheduled trip-stops:

$$\text{ETA Completeness Score} = \left( \frac{N_{\text{communicated\_trips}}}{N_{\text{scheduled\_trips}}} \right) \times 100$$

Transit networks operating above a 95% completeness threshold provide predictable user experiences.

To handle data volatility without causing user panic, user interfaces should implement a **three-tiered confidence UI structure**:

```
┌─────────────────────────────────────────────────────────────────────────┐
│ Tier 1: Verified Real-Time (Active AVL GPS Ping < 60s)                  │
│ • Pulsing live vehicle dot on route polyline                            │
│ • High-contrast countdown ("3 min") with Electric Amber / Green badge   │
├─────────────────────────────────────────────────────────────────────────┤
│ Tier 2: Predicted / Estimated (Stale GPS Ping > 60s or Interpolated)    │
│ • Static vehicle icon on map                                            │
│ • "Estimated" text tag + muted countdown ("~4 min")                     │
├─────────────────────────────────────────────────────────────────────────┤
│ Tier 3: Static Timetable Fallback (Zero Active AVL Tracking)             │
│ • Published clock schedule ("8:45 AM")                                  │
│ • Prominent "No Live Tracking" status badge (dimmed styling)            │
└─────────────────────────────────────────────────────────────────────────┘
```

Displaying a live vehicle dot moving in real time across a map provides spatial confirmation that reassures users. Seeing a physical bus dot four blocks away maintains trust even when countdown estimates fluctuate.

#### Subterranean & Complex Hub Navigation

Deep subterranean stations present spatial orientation challenges due to severe GPS signal degradation caused by concrete and steel structures. When subterranean GPS fails, users experience sudden location cone jumping and directional disorientation.

To resolve subterranean navigation, platforms must implement three deterministic tools:
1. **Platform Train Car Exit Positioning:** Advising passengers to board specific train sections (e.g., "Board cars 7–8 near the rear") aligns riders directly with destination stairs and transfer corridors. This reduces platform egress times by up to 60 seconds, often making the difference in tight connections.
2. **Deterministic Exit Mapping:** Labeling station exits using physical street corners and standardized exit codes (e.g., "Exit 4B - NW Corner of 42nd St & Broadway") bridges the transition from underground platforms to street-level walking.
3. **Step-Free Accessible Routing:** Providing step-free options requires real-time monitoring of station elevator operational status, ramp gradients, and platform-to-train gap widths. If a key elevator fails, the system must automatically re-route accessible users through an alternative accessible station.

#### Disruption Triage & Service Alerts

Generic, system-wide agency alert banners (e.g., "Q Line experiencing delays systemwide") clutter user interfaces and induce alert fatigue.

Modern alert architectures parse GTFS-RT Service Alert entities and map them directly against the user's active itinerary. Alerts surface inline directly within the step-by-step itinerary view. The system categorizes disruptions into two operational levels:
- **Informational (No Action Needed):** Delays or changes occurring on the line that do not affect the user's specific boarding, transit, or egress stations.
- **Actionable (Reroute Required):** Delays or suspensions that directly impact the user's active route. In this case, the system displays an inline alert along with a dynamic "Tap to Reroute" button.

#### High-Density Timetable UX

In high-density Asian rail networks like Tokyo, Seoul, and Hong Kong, transit platforms utilize matrix/grid departure boards rather than standard chronological lists.

Chronological vertical lists work well for simple, low-frequency routes because they present upcoming departures with minimal visual complexity. However, for high-density networks featuring multi-branch lines and local/express splits, matrix grid views are far superior. Matrices arrange time horizontally or vertically against service types, enabling riders to evaluate express versus local options across an entire hour without excessive scrolling.

---

### 2. Pedestrian Navigation & Walking Heuristics

#### Spatial Orientation vs. Turn-by-Turn

Turn-by-turn (TBT) navigation, originally created for vehicular routing, often performs poorly for pedestrians. Pedestrians do not naturally orient themselves using metric distances (e.g., "walk 250 feet and turn left"). Relying on distance-only prompts increases cognitive load, forcing users to constantly gaze at their phones, which degrades spatial memory and environmental awareness.

Pedestrian TBT navigation is further hindered by technical constraints:
- **GPS Compass Drift:** Slow walking speeds yield unreliable Doppler data, causing map orientation cones to spin erratically when users stop at intersections.
- **Multipath Interference:** Tall urban buildings reflect GPS signals, causing location markers to jump to parallel streets.
- **Cognitive Distraction:** Continuous screen fixation reduces situational awareness and impairs pedestrian safety.

#### Landmark-Based Guidance

Visual landmarks serve as primary cognitive anchors in human spatial mapping. Incorporating visible physical objects into turn prompts significantly reduces cognitive fatigue and visual search times at street corners.

Instead of instructing a user to "turn right in 200 feet onto 5th Ave," a human-centered system prompts: **"Turn right after the red brick pharmacy onto 5th Ave"**. Confirmation prompts similarly shift from numerical metrics ("proceed 0.4 miles") to visual anchors (**"walk past the park on your left"**).

To optimize visual processing, landmark density must be carefully balanced. Displaying **3 to 5 salient landmarks** along a walking route provides ideal spatial orientation guidance. Exceeding 7 landmarks increases visual clutter and impairs spatial retention. Effective landmarks are chosen based on structural uniqueness, visual permanence, and proximity to decision points.

#### Safety, Comfort, and Route Factors

Pedestrians prioritize safety, thermal comfort, and physical accessibility over raw distance minimization. Urban pathfinding engines should incorporate multi-attribute cost functions to account for these factors:

##### Shaded Microclimate Routing
Summer heat deters outdoor walking. By combining urban canopy density data, building height vectors, and real-time solar positioning, routing engines can calculate "shaded cool paths". Shaded routing reduces Physiologically Equivalent Temperature (PET) exposure, maximizing outdoor comfort:

$$\text{PET} = f(T_a, RH, v, \text{MRT})$$

Where $T_a$ is air temperature, $RH$ is relative humidity, $v$ is wind velocity, and $\text{MRT}$ is Mean Radiant Temperature (moderated by solar shading). Shaded paths may add 2–4% to total walk distance while reducing cumulative thermal exposure by over 25%.

##### Sidewalk Quality & Step-Free Surfaces
Travelers with luggage, strollers, or mobility devices require continuous step-free paths. Pathfinding engines must evaluate curb ramp availability, sidewalk width, and surface materials (avoiding cobble or broken pavement).

##### Topography & Gradient Avoidance
Pedestrian walking utility drops sharply as street slope increases. A 1% increase in slope leads to measurable drops in walking route selection. Algorithms must apply cost penalties to steep climbs for pedestrians and non-electric micro-mobility devices.

#### Ambient vs. Active Walking

Pedestrian expectations change based on travel intent:
- **Active A-to-B commuters** focus on time optimization, direct pathways, prominent visual turn arrows, and audio prompts.
- **Ambient explorers** favor open neighborhood maps, visual points of interest, silent haptic alerts, and dynamic north-up map orientations that support relaxed spatial exploration.

---

### 3. Biking, Micro-Mobility & Bike-Share (GBFS) Baseline

#### Inventory & Dock Anxiety

Bike-share users rely on real-time General Bikeshare Feed Specification (GBFS) data feeds. A major source of anxiety for bike-share riders is inventory uncertainty at both origin and destination points.

- **At the origin:** Arriving at a station only to find no working bikes—or finding e-bikes with depleted batteries—wastes time and effort. Interfaces must surface real-time bike availability broken down by vehicle type (pedal bike vs. e-bike) alongside estimated battery range.
- **At the destination:** Arriving at a station with no empty docks forces riders to search for overflow docks while incurring extra usage fees.

To mitigate destination dock anxiety, systems must implement **dynamic dock availability gating**:
- **Low Dock Risk (>3 Empty Docks):** Provides standard guidance to the selected target dock.
- **Moderate Dock Risk (1–2 Empty Docks):** Surfaces a dock warning badge and pre-selects a secondary fallback dock nearby.
- **High Dock Risk / Station Full (0 Empty Docks):** Automatically reroutes the rider to the nearest available station within a 3-minute walk.

```
┌─────────────────────────────────────────────────────────────────────────┐
│ Dynamic Dock Availability Gating                                        │
│                                                                         │
│  [Target Station] ────> Empty Docks > 3 ──> Standard Route Guidance    │
│         │                                                               │
│         ├─────────────> Empty Docks 1–2 ──> Warning + Pre-arm Fallback  │
│         │                                                               │
│         └─────────────> Empty Docks = 0 ──> Auto-Reroute to Nearest Dock│
└─────────────────────────────────────────────────────────────────────────┘
```

#### Cyclist Route Preference Hierarchies

GPS trajectory studies show that cyclists routinely accept distance detours to trade travel time for safety, comfort, and lower traffic stress.

Cyclists prioritize routes based on a clear infrastructure hierarchy:
1. **Off-Street Multi-Use Paths & Greenways:** Highest utility; fully separated from vehicular traffic.
2. **Physically Protected On-Street Cycle Tracks:** High utility; separated by concrete curbs, bollards, or parked cars.
3. **Painted Dedicated Bike Lanes on Quiet Residential Streets:** Moderate utility; low traffic volume and speed.
4. **Painted Bike Lanes on High-Speed Arterial Streets:** Low utility; elevated traffic stress.
5. **Shared Vehicular Lanes / Sharrows:** Lowest utility; high traffic stress and physical risk.

Pathfinding engines use Path-Size Logit (PSL) models to score routes based on Level of Traffic Stress (LTS). Routing engines prioritizing protected cycle tracks can increase low-stress route exposure by 31.4% while reducing high-stress road exposure by 41.5%, with only a minor 3.9% increase in total trip length. Gender and age demographics further influence stress sensitivity: female and middle-aged cyclists exhibit greater aversion to traffic stress and steep slopes, prioritizing separated infrastructure.

#### Ergonomics & Glanceability

Operating a bicycle or scooter restricts continuous visual interaction with a mobile screen. Mounted phones face glare, vibrations, and shifting light conditions. Cycling UIs must adhere to strict glanceability standards:
- **Expanded Touch Targets:** Touch targets must be expanded to at least 56x56 pt to support quick one-handed adjustments and gloved interaction.
- **High-Contrast Visual Hierarchy:** Displays must use high-contrast, WCAG AAA-compliant color palettes with prominent directional symbols.
- **Glance Duration Window:** UI layouts must allow riders to absorb key directional info within a 0.5-second glance window, replacing long text instructions with clear directional arrows and distance indicators.

---

### 4. Multimodal Chaining & Transfer Psychology

#### First-Mile / Last-Mile Integration

Multimodal journeys connect micro-mobility, public transit, and walking into continuous itineraries. Legacy mapping platforms often struggle with multimodal journeys because they evaluate transit modes in isolation rather than as chained networks.

```
                     ISOLATED TRADITIONAL ROUTING (MODE SILOS)
  [Walk 10 min] ──> [Wait at Station 8 min] ──> [Subway 15 min] ──> [Walk 12 min]
  Total Elapsed Duration: 45 minutes
  
                     OPTIMIZED MULTIMODAL CHAINING (UNIFIED TRIP)
  [Shared E-Bike 4 min] ──> [Subway 15 min] ──> [Shared Scooter 3 min]
  Total Elapsed Duration: 22 minutes
```

Effective multimodal integration requires optimizing key transfer legs:
- **Walking to Transit:** Accounting for realistic walking speeds, signal delays, and station entrance stairs.
- **Bike-Share to Express Transit:** Calculating combined times to unlock a vehicle, ride to a station, dock the bike, and walk down to the platform.
- **Transit to Micro-Mobility:** Checking real-time bike/scooter availability at the destination station before recommending a micro-mobility last-mile leg.

#### Layover Slack & Transfer Anxiety

Transfer anxiety arises when passengers face tight connections between transit legs. Users balance two competing concerns:
- **Sprint Risk:** Tight transfer windows (under 2 minutes) force users to sprint through stations, risking a missed connection.
- **Dwell Fatigue:** Excessive layover slack (over 15 minutes) leads to tedious platform waits, inflating total travel time.

To optimize transfer buffers, navigation platforms deploy **Smart Departure Engines**:
- On **high-frequency lines** (under 5-minute headways), algorithms apply tight transfer buffers (2–3 minutes) because missing a train carries low time penalties.
- On **low-frequency lines** (over 20-minute headways), algorithms apply conservative transfer buffers (6–10 minutes) to minimize the risk of a long platform wait if a connection is missed.

#### Live Dynamic Recovery

When transit delays or missed connections disrupt an active trip, the system must immediately trigger dynamic rerouting:
1. **Automated Disruption Detection:** The platform detects a missed connection by comparing live GPS telemetry against platform departure times.
2. **Instant Alternative Calculation:** The routing engine automatically evaluates nearby options, including adjacent bus lines, micro-mobility, or walking paths.
3. **One-Tap Reroute Confirmation:** The UI presents a dynamic recovery card with updated route options, requiring a single tap to update the active trip.

---

### 5. Mobile OS Integration, Ergonomics & Information Architecture

#### One-Handed Thumb-Zone Design

Modern smartphone displays present reachability challenges during single-handed use. Interfaces should place primary interactive controls within the natural reach of the user's thumb.

Key structural guidelines include:
- **Sheet Detent Ergonomics:** Information sheets use three standard detent positions:
  - **15% (Collapsed Peek):** Current trip status / next upcoming maneuver.
  - **50% (Half-Screen):** Step-by-step guidance and route itinerary.
  - **90% (Full-Screen Expanded):** Detailed timetables, reliability heatmaps, and alternative routes.
- **Map-as-Hero Viewport:** The map serves as the background canvas, with interactive sheets layered floating over the lower third.
- **Thumb-Zone Controls:** Primary call-to-action buttons—such as "Start Journey," "Reroute," or "Unlock Bike"—are anchored within the lower third of the display.

```
┌──────────────────────────────────────┐
│ [   Map Canvas (Hero Viewport)     ] │
│                                      │
│                                      │
│                                      │
├──────────────────────────────────────┤
│ 15% Detent: Glanceable Next Step     │
├──────────────────────────────────────┤
│ 50% Detent: Step-by-Step Guidance    │
├──────────────────────────────────────┤
│ [ Thumb Action: Start / Reroute ]    │
└──────────────────────────────────────┘
```

#### Glanceable Passive Monitoring

Riders should not need to keep the app open constantly to follow their journey. Modern mobile operating systems support persistent, glanceable progress tracking on lock screens and system displays.

| Integration Surface | Visual & Structural Implementation | Core Functionality & User Value |
|:---|:---|:---|
| **iOS Dynamic Island** | Compact pill view showing transfer line icon and arrival countdown. Long-press expands to detailed progress and vehicle location. | Real-time journey tracking without leaving active foreground applications. Quick gesture controls for trip adjustments. |
| **iOS Live Activities / Lock Screen** | Dynamic lock screen tile displaying live vehicle ETA, next stop, and trip progress. Visual progress bar with haptic alert triggers. | Eliminates the need to unlock the phone in crowded stations. Contextual vibration alerts signal get-off stops. |
| **watchOS Complications** | Wrist glanceable displaying distance-to-next-turn or remaining transit stops. Haptic taps signal upcoming arrival or transfer points. | Low-friction guidance while walking or riding a bicycle. Hands-free alerts prevent missed stops. |

#### Accessibility Standards

Accessibility is essential for urban transport platforms. Interfaces must comply with WCAG 2.1 AA/AAA accessibility standards across key areas:
- **Color-Vision-Deficient (CVD) Palettes:** Standard transit maps rely heavily on color coding to distinguish subway lines. For CVD accessibility (deuteranopia, protanopia), polylines must include secondary visual markers, such as distinct stroke styles (dashed, dotted, solid), numerical line badges, or high-contrast border outlines.
- **Screen Reader Timetable Traversal:** Departure grids must be formatted for clear VoiceOver and TalkBack traversal. Screen readers should read schedule data as complete contextual statements (e.g., *"N Line local train toward Forest Hills, arriving in 4 minutes at Platform 2"*) rather than isolated grid cells.
- **Step-Free Accessibility Controls:** Platform settings must allow users to permanently enable step-free routing preferences. When selected, the routing engine filters out non-accessible stations, steep paths, and non-wheelchair-compliant micro-mobility options.

---

## Actionable Recommendations & Architectural Invariants

| Domain | Key Requirement | Architectural & UI Implementation Target |
|:---|:---|:---|
| **Transit Realtime & Reliability** | Eliminate ghost buses and establish data confidence tiers. | Track ETA Completeness Score; render 3-tier confidence badges (Verified / Estimated / Static); show live vehicle dots. |
| **Subterranean Hubs** | Eliminate underground egress and transfer disorientation. | Surface platform train car exit recommendations (Front/Middle/Back) and standardized physical exit street labels (e.g. Exit 4B). |
| **Pedestrian Guidance** | Prevent cognitive fatigue and GPS cone spin. | Replace metric distance turn prompts with 3–5 salient visual landmark anchors per route; support ambient exploration mode. |
| **Microclimate Routing** | Maximize thermal comfort during extreme heat. | Multi-attribute cost function incorporating solar position, building shadows, and tree canopy to produce shaded cool paths. |
| **Micro-Mobility / GBFS** | Eliminate origin bike starvation and destination dock anxiety. | Real-time GBFS battery range overlays; 3-tier dock availability gating (>3 low risk, 1–2 moderate fallback, 0 auto-reroute). |
| **Cycling Infrastructure** | Prioritize safety and low-stress transit. | Path-Size Logit (PSL) routing scoring Level of Traffic Stress (LTS); prioritize physically separated cycle tracks and multi-use paths. |
| **Ergonomics & Glanceability** | Optimize for single-handed use and on-the-go viewing. | 15%/50%/90% bottom sheet detents; 56x56pt cycling tap targets; 0.5s glance window; native iOS Dynamic Island / Live Activities. |
| **Accessibility** | Guarantee universal transit accessibility. | CVD-safe route styling (badges + stroke differentiation); accessible screen reader statements; step-free routing filter. |
