<template>
	<Transition name="slide">
		<slot />
	</Transition>
</template>

<style lang="scss" scoped>
.slide-leave-active,
.slide-enter-active {
	transition: 200ms ease;
}
.slide-leave-to,
.slide-enter-from {
	// Slides in from the left edge (Power Automate-style side panel).
	transform: translateX(-100%);
}
</style>
