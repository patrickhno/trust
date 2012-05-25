require 'test_helper'

class AccountsControllerTest < ActionController::TestCase
  context 'with all permissions' do
    setup do
      @client = Client.create
      @account = Account.create(:client_id => @client.id) #accounts(:one)
      login_as(:system_admin)
    end

    should "get index" do
      get :index, client_id: @client
      assert_response :success
      assert_not_nil assigns(:accounts)
    end

    should "get new" do
      get :new, client_id: @client
      assert_response :success
    end

    should "create account" do
      assert_difference('Account.count') do
        post :create, client_id: @client, account: { name: @account.name }
      end

      assert_redirected_to client_account_path(@client,assigns(:account))
    end

    should "show account" do
      get :show, client_id: @client, id: @account
      assert_response :success
    end

    should "get edit" do
      get :edit, client_id: @client, id: @account
      assert_response :success
    end

    should "update account" do
      put :update, client_id: @client, id: @account, account: { name: @account.name }
      assert_redirected_to client_account_path(assigns(:account))
    end

    should "destroy account" do
      assert_difference('Account.count', -1) do
        delete :destroy, client_id: @client, id: @account
      end

      assert_redirected_to client_accounts_path
    end
  end
  
  context 'with limited permissions' do
    setup do
      @account = Account.create #accounts(:one)
      login_as(:accountant)
    end
    
    should_eventually 'deny access on ...actions....' do
      
    end
    context 'but having ownership' do
      should_eventually 'allow updates' do
      end
    end
    context 'having no ownership' do
      should_eventually 'deny access' do
      end
    end
    
  end
  
end
