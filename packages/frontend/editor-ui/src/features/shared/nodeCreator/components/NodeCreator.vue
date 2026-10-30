<script setup lang="ts">
import {
	watch,
	reactive,
	toRefs,
	computed,
	onBeforeUnmount,
	onMounted,
	inject,
	ref,
	nextTick,
} from 'vue';

import { useNodeTypesStore } from '@/app/stores/nodeTypes.store';
import { useNodeCreatorStore } from '@/features/shared/nodeCreator/nodeCreator.store';
import SlideTransition from '@/app/components/transitions/SlideTransition.vue';

import { useViewStacks } from '../composables/useViewStacks';
import { useKeyboardNavigation } from '../composables/useKeyboardNavigation';
import { useActionsGenerator } from '../composables/useActionsGeneration';
import NodesListPanel from './Panel/NodesListPanel.vue';
import { useCredentialsStore } from '@/features/credentials/credentials.store';
import { useBannersStore } from '@/features/shared/banners/banners.store';
import { useUIStore } from '@/app/stores/ui.store';
import { DRAG_EVENT_DATA_KEY } from '@/app/constants';
import { EmbeddedCanvasElementKey } from '@/app/constants/injectionKeys';
import { useSettingsStore } from '@n8n/stores/settings.store';
import { useAiGateway } from '@/app/composables/useAiGateway';
import type { NodeTypeSelectedPayload } from '@/Interface';
import { onClickOutside, useElementBounding } from '@vueuse/core';

import { N8nIconButton, OVERLAY_LAYER_SELECTOR } from '@n8n/design-system';
// elements that should not trigger onClickOutside
const OUTSIDE_CLICK_WHITELIST = [
	// different modals
	'.el-overlay-dialog',
	// reka-ui overlays (N8nPopover, N8nDialog) teleport to body
	OVERLAY_LAYER_SELECTOR,
];

export interface Props {
	active?: boolean;
	onNodeTypeSelected?: (value: NodeTypeSelectedPayload[]) => void;
}

const props = defineProps<Props>();
const { resetViewStacks } = useViewStacks();
const { registerKeyHook, attachKeydownEvent, detachKeydownEvent } = useKeyboardNavigation();
const emit = defineEmits<{
	closeNodeCreator: [];
	nodeTypeSelected: [value: NodeTypeSelectedPayload[]];
	emptyGroupSelected: [];
}>();
const uiStore = useUIStore();
const bannersStore = useBannersStore();
const settingsStore = useSettingsStore();
// Doctum fixed nodes panel: docked to the screen's left edge, open by default.
// `isPinned` (persisted) keeps it open; the store also drives NodeCreation.vue
// to hide the floating "+" while the panel is pinned.
const nodeCreatorStore = useNodeCreatorStore();

const { setActions, setMergeNodes, consumePendingInitialViewStack } = useNodeCreatorStore();
const { generateMergedNodesAndActions } = useActionsGenerator();

const state = reactive({
	nodeCreator: null as HTMLElement | null,
	mousedownInsideEvent: null as MouseEvent | null,
});

const viewStacksLength = computed(() => useViewStacks().viewStacks.length);

// An embedded editor (e.g. the Instance AI split view) renders its own header
// below the page top, so the panel aligns to that editor's canvas instead.
const embeddedCanvas = inject(EmbeddedCanvasElementKey, ref(null));
const { top: embeddedCanvasTop } = useElementBounding(embeddedCanvas);

const nodeCreatorInlineStyle = computed(() => ({
	top: `${getTopOffset()}px`,
	// The main sidebar is on the right now, so the panel hugs the left edge.
	left: '0px',
}));

function getTopOffset() {
	if (embeddedCanvas.value) {
		return embeddedCanvasTop.value;
	}

	return settingsStore.isCanvasOnly ? 0 : bannersStore.bannersHeight + uiStore.headerHeight;
}

function onMouseUpOutside() {
	if (state.mousedownInsideEvent) {
		const clickEvent = new MouseEvent('click', {
			bubbles: true,
			cancelable: true,
		});
		state.mousedownInsideEvent.target?.dispatchEvent(clickEvent);
		state.mousedownInsideEvent = null;
		unBindOnMouseUpOutside();
	}
}
function unBindOnMouseUpOutside() {
	document.removeEventListener('mouseup', onMouseUpOutside);
	document.removeEventListener('touchstart', onMouseUpOutside);
}
function onMouseUp() {
	state.mousedownInsideEvent = null;
	unBindOnMouseUpOutside();
}
function onMouseDown(event: MouseEvent) {
	state.mousedownInsideEvent = event;
	document.addEventListener('mouseup', onMouseUpOutside);
	document.addEventListener('touchstart', onMouseUpOutside);
}
function onDragOver(event: DragEvent) {
	event.preventDefault();
}
function onDrop(event: DragEvent) {
	if (!event.dataTransfer) {
		return;
	}

	const dragData = event.dataTransfer.getData(DRAG_EVENT_DATA_KEY);
	const nodeCreatorBoundingRect = (state.nodeCreator as Element).getBoundingClientRect();

	// Abort drag end event propagation if dropped inside nodes panel
	if (
		dragData &&
		event.pageX >= nodeCreatorBoundingRect.x &&
		event.pageY >= nodeCreatorBoundingRect.y
	) {
		event.stopPropagation();
	}
}

const { fetchConfig: fetchAiGatewayConfig } = useAiGateway();

onMounted(() => {
	void fetchAiGatewayConfig();
});

watch(
	() => props.active,
	(isActive) => {
		if (!isActive) {
			// Pinned panel: keep the current view — the panel stays visible, so
			// emptying the view stack would blank it.
			if (nodeCreatorStore.isPinned) return;
			resetViewStacks();
			consumePendingInitialViewStack();
		}
	},
);

// Close node creator when the last view stacks is closed (skipped while pinned:
// a pinned panel never closes itself — it can only be collapsed by the user).
watch(viewStacksLength, (value) => {
	if (value === 0) {
		if (nodeCreatorStore.isPinned) {
			// Repopulate from the root view instead of closing.
			panelKey.value += 1;
			return;
		}
		emit('closeNodeCreator');
	}
});

registerKeyHook('NodeCreatorCloseEscape', {
	keyboardKeys: ['Escape'],
	handler: () => {
		// Pinned panel ignores Escape — it only closes via the collapse button.
		if (nodeCreatorStore.isPinned) return;
		emit('closeNodeCreator');
	},
});

watch(
	() => ({
		httpOnlyCredentials: useCredentialsStore().httpOnlyCredentialTypes,
		nodeTypes: useNodeTypesStore().visibleNodeTypes,
	}),
	({ nodeTypes, httpOnlyCredentials }) => {
		const { actions, mergedNodes } = generateMergedNodesAndActions(nodeTypes, httpOnlyCredentials);

		setActions(actions);
		setMergeNodes(mergedNodes);
	},
	{ immediate: true },
);
const { nodeCreator } = toRefs(state);
// Remount key for the list panel. Used to repopulate a pinned panel from its
// root view if its view stack ever drains (instead of closing it).
const panelKey = ref(0);

// Doctum pinned panel: NodesListPanel attaches a global keydown listener that
// captures arrows/Enter/Escape app-wide. That is only wanted while the creator
// is actually in use — open (active) or hovered/focused (pinned). Otherwise
// the canvas and NDV would lose their own key handling.
const isPointerInsidePanel = ref(false);
const isFocusInsidePanel = ref(false);
const shouldCaptureKeyboard = computed(
	() => props.active || isPointerInsidePanel.value || isFocusInsidePanel.value,
);

function syncKeyboardCapture() {
	if (shouldCaptureKeyboard.value) attachKeydownEvent();
	else detachKeydownEvent();
}

function onPanelMouseEnter() {
	isPointerInsidePanel.value = true;
}

function onPanelMouseLeave() {
	isPointerInsidePanel.value = false;
}

function onPanelFocusIn() {
	isFocusInsidePanel.value = true;
}

function onPanelFocusOut(event: FocusEvent) {
	const nextTarget = event.relatedTarget;
	const panel = state.nodeCreator;
	isFocusInsidePanel.value =
		nextTarget instanceof Node && panel !== null && panel.contains(nextTarget);
}

watch([shouldCaptureKeyboard, panelKey], () => {
	// After a panelKey remount, NodesListPanel re-attaches on mount; re-sync on
	// the next tick so a disengaged panel releases the listener again.
	void nextTick(() => syncKeyboardCapture());
});

onMounted(() => {
	// Runs after children mount, so it can undo NodesListPanel's own attach
	// when the pinned panel is visible but not engaged.
	syncKeyboardCapture();
});

function onCollapse() {
	// Unpin first so the close path below isn't swallowed by the pinned guard,
	// then reset the view stack so reopening starts from the root list.
	nodeCreatorStore.isPinned = false;
	emit('closeNodeCreator');
	resetViewStacks();
}

function onExpand() {
	nodeCreatorStore.isPinned = true;
}

onBeforeUnmount(() => {
	unBindOnMouseUpOutside();
	// Release the global key listener if the panel goes away while engaged.
	detachKeydownEvent();
});

onClickOutside(
	nodeCreator,
	() => {
		// Pinned panel stays open regardless of clicks elsewhere.
		if (nodeCreatorStore.isPinned) return;
		emit('closeNodeCreator');
	},
	{ ignore: OUTSIDE_CLICK_WHITELIST },
);
</script>

<template>
	<div>
		<aside :class="$style.nodeCreatorScrim" />
		<N8nIconButton
			variant="outline"
			v-if="active"
			:class="$style.close"
			icon="x"
			aria-label="Close Node Creator"
			@click="emit('closeNodeCreator')"
		/>
		<SlideTransition>
			<div
				v-if="active || nodeCreatorStore.isPinned"
				ref="nodeCreator"
				:class="{ [$style.nodeCreator]: true }"
				:style="nodeCreatorInlineStyle"
				data-test-id="node-creator"
				@dragover="onDragOver"
				@drop="onDrop"
				@mousedown="onMouseDown"
				@mouseup="onMouseUp"
				@mouseenter="onPanelMouseEnter"
				@mouseleave="onPanelMouseLeave"
				@focusin="onPanelFocusIn"
				@focusout="onPanelFocusOut"
			>
				<NodesListPanel
					:key="panelKey"
					@node-type-selected="onNodeTypeSelected"
					@empty-group-selected="emit('emptyGroupSelected')"
				/>
				<N8nIconButton
					:class="$style.collapseButton"
					variant="outline"
					size="small"
					icon="chevron-left"
					aria-label="Collapse nodes panel"
					data-test-id="collapse-nodes-panel-button"
					@click="onCollapse"
				/>
			</div>
		</SlideTransition>
		<N8nIconButton
			v-if="!active && !nodeCreatorStore.isPinned"
			:class="$style.expandTab"
			variant="outline"
			size="small"
			icon="chevron-right"
			aria-label="Expand nodes panel"
			data-test-id="expand-nodes-panel-button"
			@click="onExpand"
		/>
	</div>
</template>

<style module lang="scss">
@use '@/app/css/variables' as *;

:global(strong) {
	font-weight: var(--font-weight--medium);
}
.nodeCreator {
	--node-creator--width: #{$node-creator-width};
	--node-creator--icon--color: var(--node--icon--color--neutral);
	position: fixed;
	top: $header-height;
	bottom: 0;
	// Doctum: docked to the screen's left edge (the main sidebar is on the
	// right now). Power Automate-style actions panel.
	left: 0;
	z-index: var(--node-creator--z);
	width: var(--node-creator--width);
	color: $node-creator-text-color;
}

// Drawer handle on the panel's right edge: collapses the pinned panel.
.collapseButton {
	position: absolute;
	top: 50%;
	right: -12px;
	transform: translateY(-50%);
	z-index: calc(var(--node-creator--z) + 1);
	background: var(--color--background--surface);
	border: var(--border);
	border-radius: var(--radius--sm);
	box-shadow: var(--shadow--xs);
}

// Vertical tab on the screen's left edge: re-expands the collapsed panel.
.expandTab {
	position: fixed;
	top: 50%;
	left: 0;
	transform: translateY(-50%);
	z-index: var(--node-creator--z);
	background: var(--color--background--surface);
	border: var(--border);
	border-left: none;
	border-radius: 0 var(--radius--sm) var(--radius--sm) 0;
	box-shadow: var(--shadow--xs);
}

.nodeCreatorScrim {
	position: fixed;
	top: $header-height;
	right: 0;
	bottom: 0;
	left: 0;
	opacity: 0;
	z-index: 1;
	background: var(--dialog--overlay--color--background);
	pointer-events: none;
	transition: opacity 200ms ease-in-out;

	&.active {
		opacity: 0.7;
	}
}

.close {
	position: absolute;
	z-index: calc(var(--node-creator--z) + 1);
	top: var(--spacing--xs);
	right: var(--spacing--xs);
	background: transparent;
	border: 0;
	display: none;
}

@media screen and (max-width: #{$node-creator-width}) {
	.nodeCreator {
		--node-creator--width: 100vw;
	}

	.close {
		display: inline-flex;
	}
}
</style>
