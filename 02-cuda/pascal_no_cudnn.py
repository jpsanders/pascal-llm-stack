# Pascal (sm_61) fix: cuDNN 9.x cannot initialize on this GPU/driver combo
# (CUDNN_STATUS_NOT_INITIALIZED even on an idle card). PyTorch's native CUDA
# conv kernels (im2col + cuBLAS) work fine, so cuDNN is disabled globally.
# This module must import early; it registers no nodes.
# See jpsanders/pascal-llm-stack for the full story.
import torch
torch.backends.cudnn.enabled = False

NODE_CLASS_MAPPINGS = {}
WEB_DIRECTORY = None
