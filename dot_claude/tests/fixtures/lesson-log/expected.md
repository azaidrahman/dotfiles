---
tags:
  - tech/learning/lesson
topic: Flannel
started: 2026-08-30
status: probing
---

> [!quote] YOU
> teach me flannel

> [!abstract] TUTOR
> Let us start. A pod on node A sends a packet to a pod on node B.

> [!question] Question
> What does the packet hit first after the veth?
>
> 1. cni0 bridge
> 2. flannel.1
> 3. I don't know

> [!quote] YOU
> cni0 bridge

> [!abstract] TUTOR
> Correct. The bridge is the first hop.
>
> ```mermaid
> graph TD
>   A[packet] --> B[cni0]
> ```

> [!quote] YOU
> What about multi-homing?

> [!question] Question
> Does flannel support VXLAN?
>
> 1. Yes
> 2. No

> [!question] Question
> Does flannel support host-gw?
>
> 1. Yes
> 2. No

> [!quote] YOU
> Yes
> No
