# CirculTrade: Decentralized Escrow for Circular Economy

> **A Trust-Minimized Smart Contract Solution to Information Asymmetry and Moral Hazard in the University Second-Hand Market**
> 
> **Network:** LACNet (EVM-Compatible, Pro-Testnet)
> **Geographic Focus:** Peru & Latin America — Architecture: Globally Scalable

---

## 👥 Team Members and Roles
* **Jean Pierre Guillermo Llantoy** – Smart Contract Developer & Backend Integration (Solidity architecture, escrow logic, LACNet deployment).
* **Josue Manuel Velasquez Mendizabal** – Frontend Developer & Product Designer (dApp interface, wallet-abstraction onboarding flow).
* **Leonardo Esteban Accho Parian** – Economic Research & Business Development Lead (Microeconomic modeling, technical documentation, and university partnerships).

---

## 🛑 Problem Description

Latin America remains structurally locked into a linear “take-make-dispose” model of consumption, and Peru is no exception. Despite the enactment of a national Circular Economy Law in 2020 (Legislative Decree No. 1501, amending Law No. 1278), a recent peer-reviewed baseline assessment of a riverine city in northern Peru found that a formal waste valorization rate of under 5% persists nationally, well behind the law's statutory ambitions. 

University students sit at the epicenter of this linear pattern at a micro-economic level. Each academic cycle, cohorts of students purchase textbooks, calculators, laptops, furniture, and clothing that are subsequently discarded, stored unused, or abandoned at the end of a semester rather than resold into a secondary market. Two closely related market failures explain why this reusable stock fails to recirculate: information asymmetry and the transaction costs it generates.

### The "Market for Lemons"
The first is a direct instance of Akerlof's (1970) “Market for Lemons”. In the unmediated peer-to-peer trade that dominates student resale, the seller has far more information about an item's true condition than the buyer can verify before payment. Because a buyer cannot distinguish a genuinely well-kept item from a failing one, rational buyers will only pay a price reflecting the pooled, average expected quality of listings:

$E[V] = \theta \cdot q_H + (1 - \theta) \cdot q_L$

where $\theta$ is the buyer's prior belief that a given listing is high-quality ($q_H$) rather than low-quality ($q_L$). This leaves a disproportionate share of lower-quality goods in circulation, further eroding buyer confidence in a self-reinforcing spiral that shrinks the second-hand market below its efficient size.

### Moral Hazard
The second failure is moral hazard, or hidden action: even when a price is agreed, a buyer who pays first has no recourse if the seller never ships the item, ships the wrong item, or misrepresents its condition. The binding constraint on the student second-hand market is not price or product availability; it is the absence of a credible mechanism to guarantee the counterparty's behavior[cite: 2].

---

## 💡 Solution Abstract

CirculTrade is a decentralized escrow smart contract on the EVM-compatible LACNet network that resolves information asymmetry and moral hazard in the peer-to-peer second-hand market for university students. It locks the buyer's payment and releases it to the seller only after the buyer confirms the item arrived in the agreed condition, replacing costly interpersonal trust with programmable, verifiable trust[cite: 2]. This lowers transaction costs and turns reuse into a genuinely competitive alternative to buying new.

---

## ⚙️ Technologies Used

* **Solidity:** The escrow logic — locking funds, verifying a buyer's confirmation, and conditionally releasing or refunding payment — is a textbook use case for Solidity's explicit state-machine model.
* **Ethereum Virtual Machine (EVM):** Building for the EVM maximizes tooling maturity and wallet compatibility, lowering the long-term cost of auditing and maintaining the project.
* **LACNet (LACChain Pro-Testnet):** A non-profit, public-permissioned blockchain orchestrator for Latin America and the Caribbean. Its gas-less, flat-membership model converts an uncertain marginal cost into a predictable, near-zero one — precisely the condition transaction-cost economics prescribes for a high-frequency, low-value market to clear efficiently.

---
*Developed for the “Innovating for a Sustainable Future” Hackathon - July 2026*
