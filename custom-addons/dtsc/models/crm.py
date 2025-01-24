from odoo import models, fields, api

import logging

_logger = logging.getLogger(__name__)

class CrmLead(models.Model):
    _inherit = 'crm.lead'
    
    checkout_id = fields.Many2one(
        'dtsc.checkout',
        string="關聯大圖訂單",
        readonly=True,
        help="與當前商機關聯的大圖訂單"
    )

    checkout_count = fields.Integer(
        string="大圖訂單數量",
        compute="_compute_checkout_count",
        store=False,
        help="計算與當前商機關聯的大圖訂單數量"
    )

    @api.depends('checkout_id')
    def _compute_checkout_count(self):
        for lead in self:
            lead.checkout_count = self.env['dtsc.checkout'].search_count([('crm_lead_id', '=', lead.id)])
            
    def action_open_checkout(self):
        self.ensure_one()
        
        # 创建大图订单
        checkout = self.env['dtsc.checkout'].with_context(from_crm=True).create({
            'crm_lead_id': self.id,
        })

        # 关联创建的订单
        self.checkout_id = checkout.id

        return {
            'type': 'ir.actions.act_window',
            'name': '新增大圖訂單',
            'res_model': 'dtsc.checkout',
            'view_mode': 'form',
            'res_id': checkout.id,
            'target': 'current',
        }

        
    def action_view_related_checkout(self):
        """
        从CRM进入时，显示与当前商机关联的所有订单状态。
        """
        self.ensure_one()
        action = self.env.ref('dtsc.action_window').read()[0]
        # 强制显示所有状态，包括 "待确认"
        action['domain'] = [('crm_lead_id', '=', self.id)]
        return action


class CheckoutInherit(models.Model):
    _inherit = 'dtsc.checkout'

    crm_lead_id = fields.Many2one(
        'crm.lead',
        string="關聯商機",
        help="與此訂單關聯的商機"
    )

    checkout_order_state = fields.Selection(selection_add=[
        ('waiting_confirmation', '待確認')
    ], ondelete={'waiting_confirmation': 'set default'})

    @api.model
    def create(self, vals):
        """
        如果从 CRM 创建订单，设置状态为"待确认"。
        """
        _logger.info("Creating Checkout - Incoming Vals: %s", vals)  # 打印传入的 vals

        # 检查上下文，确定是否来自 CRM
        if self.env.context.get('from_crm', False):  
            vals['checkout_order_state'] = 'waiting_confirmation'
            _logger.info("Setting checkout_order_state to 'waiting_confirmation'")

        # 调用父类的 create 方法
        result = super(CheckoutInherit, self).create(vals)

        _logger.info("Created Checkout - Result: %s", result)
        return result
    
    def action_confirm_to_draft(self):
        """
        确认按钮逻辑：
        - 检查是否选择了客户
        - 将客户的分类更新到订单上
        - 将状态改为草稿
        """
        for record in self:
            if not record.customer_id:
                raise ValueError("請選擇客戶") 

            # 更新订单上的客户分类
            if record.customer_id.customclass_id:
                record.customer_class_id = record.customer_id.customclass_id.id
            
            # 修改状态为草稿
            record.checkout_order_state = 'draft'